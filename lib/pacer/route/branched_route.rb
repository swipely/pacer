module Pacer
  class BranchedRoute
    include Route
    include RouteOperations
    include MixedRouteModule

    def initialize(back, block)
      @back = back
      @branches = []
      @split_pipe = CopySplitPipe
      @merge_pipe = RobinMergePipe
      branch &block
    end

    def branch(&block)
      if @back.vertices_route?
        branch_start = VerticesIdentityRoute.new(self).route
      elsif @back.edges_route?
        branch_start = EdgesIdentityRoute.new(self).route
      elsif
        branch_start = MixedIdentityRoute.new(self).route
      end
      branch = yield(branch_start)
      @branches << [branch_start, branch.route] if branch and branch != branch_start
      self
    end

    def branch_count
      @branches.count
    end

    def root?
      false
    end

    def merge
      MixedElementsRoute.new(self)
    end

    def exhaustive
      merge_pipe(ExhaustiveMergePipe)
    end

    def merge_pipe(pipe_class)
      @merge_pipe = pipe_class
      self
    end

    def split_pipe(pipe_class)
      @split_pipe = pipe_class
      self
    end

    protected

    def iterator(is_path_iterator)
      pipe = source(is_path_iterator)
      add_branches_to_pipe(pipe, is_path_iterator)
    end

    def add_branches_to_pipe(pipe, is_path_iterator)
      split_pipe = @split_pipe.new @branches.count
      split_pipe.set_starts pipe
      idx = 0
      pipes = @branches.map do |branch_start, branch_end|
        branch_start.new_identity_pipe.set_starts(split_pipe.get_split(idx))
        idx += 1
        branch_end.iterator(is_path_iterator)
      end
      pipe = @merge_pipe.new
      pipe.set_starts(pipes)
      if is_path_iterator
        pipe = PathIteratorWrapper.new(pipe, pipe)
      end
      pipe
    end

    def inspect_class_name
      "#{super} { #{ @branches.map { |s, e| e.inspect }.join(' | ') } }"
    end

    def route_class
      MixedElementsRoute
    end
  end
end
