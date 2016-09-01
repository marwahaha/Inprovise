# Execution context for Inprovise
#
# Author::    Martin Corino
# License::   Distributes under the same license as Ruby

require 'open3'
require 'ostruct'

class Inprovise::ExecutionContext

  class DSL
    def initialize(context)
      @context = context
    end

    def method_missing(meth, *args)
      @context.config.send(meth, *args)
    end

    def node
      @context.node
    end

    def config
      @context.config
    end

    def as(user, &blk)
      @context.as(user, &blk)
    end

    def in_dir(path, &blk)
      @context.in_dir(path, &blk)
    end

    def run_local(cmd)
      @context.run_local(cmd)
    end

    def run(cmd, opts={})
      @context.run(cmd, opts)
    end

    def sudo(cmd, opts={})
      @context.sudo(cmd, opts)
    end

    def env(var)
      @context.env(var)
    end

    def log(msg=nil)
      @context.log(msg)
    end

    def upload(from, to)
      @context.upload(from, to)
    end

    def download(from, to)
      @context.download(from, to)
    end

    def mkdir(path)
      @context.mkdir(path)
    end

    def remove(path)
      @context.delete(path)
    end

    def local(path)
      @context.local(path)
    end

    def remote(path)
      @context.remote(path)
    end

    def template(path)
      @context.template(path)
    end

    def trigger(action_ref, *args)
      @context.trigger(action_ref, *args)
    end

    def binary_exists?(binary)
      @context.binary_exists?(binary)
    end
  end

  attr_reader :node, :config
  attr_accessor :script

  def initialize(node, log, index, config=nil)
    @node = node
    @log = log
    @node.log_to(@log)
    @config = init_config(config || @node.config)
    @index = index
    @script = nil
  end

  def init_config(hash)
    hash.to_h.reduce(OpenStruct.new(hash)) do |os,(k,v)|
      os[k] = init_config(v) if Hash === v
      os
    end
  end

  def exec(blk, *args)
    if args.empty?
      DSL.new(self).instance_eval(&blk)
    else
      DSL.new(self).instance_exec(*args, &blk)
    end
  end

  def as(user, &blk)
    for_user(user).exec(blk)
  end

  def in_dir(path, &blk)
    rc = nil
    old_cwd = @node.helper.set_cwd(path)
    begin
      rc = exec(blk)
    ensure
      @node.helper.set_cwd(old_cwd)
    end
    rc
  end

  def for_user(user)
    return self if user.nil? || user == node.user
    new_node = @node.for_user(user)
    new_log = @log.clone_for_node(new_node)
    self.class.new(new_node, new_log, @index, @config)
  end

  def run_local(cmd)
    @log.local(cmd)
    stdout, stderr, status = Open3.capture3(cmd)
    @log.stdout(stdout)
    @log.stderr(stderr)
  end

  def run(cmd, opts={})
    @node.run(cmd, opts)
  end

  def sudo(cmd, opts={})
    @node.sudo(cmd, opts)
  end

  def env(var)
    @node.env(var)
  end

  def log(msg=nil)
    @log.log(msg) if msg
    @log
  end

  def upload(from, to)
    @node.upload(from, to)
  end

  def download(from, to)
    @node.download(from, to)
  end

  def mkdir(path)
    @node.mkdir(path)
  end

  def remove(path)
    @node.delete(path)
  end

  def copy(from, to)
    @node.copy(from, to)
  end

  def move(from, to)
    @node.move(from, to)
  end

  def local(path)
    Inprovise::LocalFile.new(self, path)
  end

  def remote(path)
    Inprovise::RemoteFile.new(self, path)
  end

  def set_permissions(path, mask)
    @node.set_permissions(path, mask)
  end

  def set_owner(path, user, group=nil)
    @node.set_owner(path, user, group)
  end

  def template(path)
    Inprovise::Template.new(path, self)
  end

  def trigger(action_ref, *args)
    action_name, pkg_name = *action_ref.split(':', 2).reverse
    pkg = @script
    pkg = @index.get(pkg_name) if pkg_name
    action = pkg.actions[action_name] if pkg
    raise Inprovise::MissingActionError.new(action_ref) unless action
    curtask = @node.log.set_task(action_ref)
    curscript = @script
    @script = pkg
    @script.merge_configuration(self.config)
    begin
      exec(action, *args)
    ensure
      @script = curscript
      @node.log.set_task(curtask)
    end
  end

  def binary_exists?(binary)
    @node.binary_exists?(binary)
  end
end

class Inprovise::MissingActionError < StandardError
  def initialize(action_ref)
    @action_ref = action_ref
  end

  def message
    "Action '#{@action_ref}' could not be found."
  end
end

class Inprovise::MockExecutionContext < Inprovise::ExecutionContext
  def run(cmd)
    @log.mock_execute(cmd)
    ''
  end

  def sudo(cmd)
    @log.mock_execute "sudo #{cmd}"
    ''
  end

  def upload(from, to)
    @log.mock_execute("UPLOAD: #{from} => #{to}")
  end

  def download(from, to)
    @log.mock_execute("DOWLOAD: #{to} <= #{from}")
  end

  def mkdir(path)
    @log.mock_execute("MKDIR: #{path}")
  end

  def remove(path)
    @log.mock_execute("REMOVE: #{path}")
  end

  def copy(from, to)
    @log.mock_execute("COPY: #{from} #{to}")
  end

  def set_permissions(path, mask)
    @log.mock_execute("SET_PERMISSIONS: #{path} #{'%o' % mask}")
  end

  def set_owner(path, user, group=nil)
    @log.mock_execute("SET_OWNER: #{path} #{user} #{group ? " #{group}" : ''}")
  end
end
