require 'java'
require 'vendor/pipes-0.1-SNAPSHOT-standalone.jar'
require 'pp'

module Pacer
  import com.tinkerpop.pipes.AbstractPipe
  import com.tinkerpop.pipes.filter.RandomFilterPipe
  import com.tinkerpop.pipes.filter.DuplicateFilterPipe
  import com.tinkerpop.pipes.filter.RangeFilterPipe
  import com.tinkerpop.pipes.filter.ComparisonFilterPipe
  import com.tinkerpop.pipes.pgm.PropertyFilterPipe
  import com.tinkerpop.pipes.pgm.GraphElementPipe
  import com.tinkerpop.pipes.pgm.VertexEdgePipe
  import com.tinkerpop.pipes.pgm.EdgeVertexPipe
  import java.util.NoSuchElementException

  import com.tinkerpop.blueprints.pgm.Graph;
  import com.tinkerpop.blueprints.pgm.impls.neo4j.Neo4jGraph;
  import java.util.Iterator


  import com.tinkerpop.blueprints.pgm.impls.neo4j.Neo4jVertex
  import com.tinkerpop.blueprints.pgm.impls.neo4j.Neo4jEdge


  def self.neo4j(path)
    graph = Neo4jGraph.new(path)
    at_exit do
      begin
        graph.shutdown
      rescue Exception, StandardError => e
        pp e
      end
    end
    graph
  end

  class PathIteratorWrapper
    attr_reader :pipe, :previous, :value

    def initialize(pipe, previous = nil)
      @pipe = pipe
      @previous = previous if previous.class == self.class
    end

    def path
      if @previous
        prev_path = @previous.path
        if prev_path.last == @value
          prev_path
        else
          prev_path + [@value]
        end
      else
        [@value]
      end
    end

    def next
      @value = @pipe.next
    end
  end

  class VariableStoreIteratorWrapper
    def initialize(pipe, vars, variable_name)
      @pipe = pipe
      @vars = vars
      @variable_name = variable_name
    end

    def next
      @vars[@variable_name] = @pipe.next
    end
  end

  class BlockFilterPipe < AbstractPipe
    attr_accessor :starts

    def configure(starts, back, block)
      @starts = starts
      @back = back
      @block = block
      @count = 0
    end

    def processNextStart()
      while s = @starts.next
        path = @back.class.new(s)
        path.send(:back=, @back)
        path.pipe_class = nil
        @count += 1
        path.info = "temp #{ @count }"
        path.extend SingleRoute
        ok = @block.call path
        return s if ok
      end
      raise NoSuchElementException.new
    end
  end


  class EnumerablePipe < AbstractPipe
    def set_enumerable(enumerable)
      case enumerable
      when Enumerable::Enumerator
        @enumerable = enumerable
      when Enumerable
        @enumerable = enumerable.to_enum
      else
        @enumerable = [enumerable].to_enum
      end
    end

    def processNextStart()
      @enumerable.next
    rescue
      raise NoSuchElementException.new
    end
  end


  class LabelsFilterPipe < AbstractPipe
    attr_accessor :starts

    def set_labels(labels)
      @labels = labels.map { |label| label.to_s.to_java }
    end

    def set_starts(starts)
      @starts = starts
    end

    def processNextStart()
      while edge = @starts.next
        if @labels.include? edge.get_label
          return edge;
        end
      end
      raise NoSuchElementException.new
    end
  end

  module SingleRoute
    def [](name)
      map do |element|
        element.get_property(name.to_s)
      end.first
    end

    def label
      labels.first
    end

    def id
      ids.first
    end

    def current
      first
    end

    def ==(element)
      current == element or super
    end
  end

  module Route
    module RouteClassMethods
      def vertex_path(name)
      end

      def edge_path(name)
      end

      def path(name)
      end

      def pipe_filter(back, pipe_class, *args, &block)
        f = new(back, nil, block, *args)
        f.pipe_class = pipe_class
        f
      end
    end

    def self.included(target)
      target.send :include, Enumerable
      target.extend RouteClassMethods
    end

    def initialize_path(back = nil, filters = nil, block = nil, *pipe_args)
      if back.is_a? Route
        @back = back
      else
        @source = back
      end
      @filters = filters || []
      @block = block
      @pipe_args = pipe_args
    end

    def filters
      @filters ||= []
    end

    def block
      @block
    end

    def back
      @back
    end

    def info
      @info
    end

    def info=(str)
      @info = str
    end

    def graph=(graph)
      @graph = graph
    end

    def graph
      @graph ||= (@back || @source).graph
    end

    def pipe_class=(klass)
      @pipe_class = klass
    end

    def from_graph?(g)
      graph == g
    end

    def root?
      !@source.nil? or @back.nil?
    end

    def vars
      if @back
        @back.vars
      else
        @vars
      end
    end

    def except(path)
      if path.is_a? Symbol
        route_class.pipe_filter(self, nil) { |v| v.current != v.vars[path] }
      else
        path = [path] unless path.is_a? Enumerable
        route_class.pipe_filter(self, CollectionFilterPipe, path, ComparisonFilterPipe::Filter::EQUAL)
      end
    end

    def only(path)
      if path.is_a? Symbol
        route_class.pipe_filter(self, nil) { |v| v.current == v.vars[path] }
      else
        path = [path] unless path.is_a? Enumerable
        route_class.pipe_filter(self, CollectionFilterPipe, path, ComparisonFilterPipe::Filter::NOT_EQUAL)
      end
    end

    def each
      iter = iterator
      g = graph
      while item = iter.next
        item.graph = g
        yield item
      end
    rescue NoSuchElementException
      self
    end

    def each_path
      iter = iterator(true)
      g = graph
      while item = iter.next
        path = iter.path
        path.each { |item| item.graph = g }
        yield path
      end
    rescue NoSuchElementException
      self
    end

    def inspect
      "#<#{inspect_strings.join(' -> ')}>"
    end

    def ==(other)
      other.class == self.class and
        other.back == @back and
        other.instance_variable_get('@source') == @source
    end

    protected

    def back=(back)
      @back = back
    end

    def source(path_iterator = false)
      if @source
        if path_iterator
          PathIteratorWrapper.new(iterator_from_source(@source))
        else
          iterator_from_source(@source)
        end
      else
        @back.send(:iterator, path_iterator)
      end
    end

    def iterator_from_source(src)
      if src.is_a? Proc
        iterator_from_source(src.call)
      elsif src.is_a? Iterator
        src
      elsif src
        pipe = EnumerablePipe.new
        pipe.set_enumerable src
        pipe
      end
    end

    def iterator(path_iterator = false)
      @vars = {}
      pipe = nil
      prev_path_iterator = nil
      if @pipe_class
        prev_path_iterator = prev_pipe = source(path_iterator)
        pipe = @pipe_class.new(*@pipe_args)
        pipe.set_starts prev_pipe
      else
        prev_path_iterator = pipe = source(path_iterator)
      end
      pipe = filter_pipe(pipe, filters, @block)
      pipe = yield pipe if block_given?
      if path_iterator
        pipe = PathIteratorWrapper.new(pipe, prev_path_iterator)
      end
      pipe
    end

    def inspect_strings
      ins = []
      ins += @back.inspect_strings unless root?

      if @pipe_class
        ps = @pipe_class.name
        pipeargs = @pipe_args.map { |a| a.to_s }.join(', ')
        if ps =~ /FilterPipe$/
          ps = ps.split('::').last.sub(/FilterPipe/, '')
          pipeargs = @pipe_args.map { |a| a.to_s }.join(', ')
          ps = "#{ps}(#{pipeargs})"
        else
          ps = @pipe_args
        end
      end
      fs = "#{filters.inspect}" if filters.any?
      bs = '&block' if @block

      s = "#{self.class.name.split('::').last.sub(/Route$/, '')}"
      s = "#{s} #{ @info }" if @info
      if ps or fs or bs
        s = "#{s}(#{ [ps, fs, bs].compact.join(', ') })"
      end
      ins << s
      ins
    end

    def filter_pipe(pipe, args_array, block)
      if args_array and args_array.any?
        pipe = args_array.select { |arg| arg.is_a? Hash }.inject(pipe) do |p, hash|
          hash.inject(p) do |p2, (key, value)|
            new_pipe = PropertyFilterPipe.new(key.to_s, value.to_java, ComparisonFilterPipe::Filter::NOT_EQUAL)
            new_pipe.set_starts p2
            new_pipe
          end
        end
      end
      if block
        new_pipe = BlockFilterPipe.new
        new_pipe.configure(pipe, self, block)
        pipe = new_pipe
      end
      pipe
    end
  end

  module RouteOperations
    def paths
      PathsRoute.new(self)
    end

    # bias is the chance the element will be returned from 0 to 1 (0% to 100%)
    def random(bias = 0.5)
      route_class.pipe_filter(self, RandomFilterPipe, bias)
    end

    def uniq
      route_class.pipe_filter(self, DuplicateFilterPipe)
    end

    def [](prop_or_subset)
      case prop_or_subset
      when String, Symbol
        # could use PropertyPipe but that would mean supporting objects that I don't think
        # would have much purpose.
        map do |element|
          element.get_property(prop_or_subset.to_s)
        end
      when Fixnum
        route_class.pipe_filter(self, RangeFilterPipe, prop_or_subset, prop_or_subset + 1)
      when Range
        end_index = prop_or_subset.end
        end_index += 1 unless prop_or_subset.exclude_end?
        route_class.pipe_filter(self, RangeFilterPipe, prop_or_subset.begin, end_index)
      when Array
      end
    end

    def ids
      map { |e| e.id }
    end

    def group_count(*props)
      result = Hash.new(0)
      props = props.map { |p| p.to_s }
      if props.empty? and block_given?
        each { |e| result[yield(e)] += 1 }
      elsif block_given?
        each do |e|
          key = props.map { |p| e.get_property(p) }
          key << yield(e)
          result[key] += 1
        end
      elsif props.any?
        each do |e|
          result[props.map { |p| e.get_property(p) }] += 1
        end
      end
      result
    end

    def delete!
      map { |e| e.delete! }
    end

    def as(name)
      if self.is_a? VerticesRouteModule
        VertexVariableRoute.new(self, name)
      elsif self.is_a? EdgesRouteModule
        EdgeVariableRoute.new(self, name)
      end
    end

    protected

    def has_routable_class?
      true
    end

    def route_class
      route = self
      route = route.back until route.has_routable_class?
      route.class
    end
  end


  class PathsRoute
    include Route

    def initialize(back)
      @back = back
    end

    alias each each_path

    def root?
      false
    end

    def transpose
      to_a.transpose
    end

    protected

    def has_routable_class?
      false
    end
  end


  module VariableRouteModule
    def initialize(back, variable_name)
      @back = back
      @variable_name = variable_name
    end

    def root?
      false
    end

    protected

    def iterator(*args)
      super do |pipe|
        VariableStoreIteratorWrapper.new(pipe, vars, @variable_name)
      end
    end

    def has_routable_class?
      false
    end
  end


  module GraphRoute
    def v(*filters, &block)
      path = VerticesRoute.new(proc { self.get_vertices }, filters, block)
      path.pipe_class = nil
      path.graph = self
      path
    end

    def e(*filters, &block)
      path = EdgesRoute.new(proc { self.get_edges }, filters, block)
      path.pipe_class = nil
      path.graph = self
      path
    end

    def [](id)
      vertex id
    end

    def result
      self
    end

    def root?
      true
    end
  end


  class Neo4jGraph
    include Route
    include RouteOperations
    include GraphRoute

    def vertex(id)
      if v = get_vertex(id)
        v.graph = self
        v
      end
    end

    def edge(id)
      if e = get_edge(id)
        e.graph = self
        e
      end
    end

    def load_vertices(ids)
      ids.map do |id|
        vertex id rescue nil
      end.compact
    end

    def load_edges(ids)
      ids.map do |id|
        edge id rescue nil
      end.compact
    end

    def vertex_name
      @vnp
    end

    def vertex_name=(name_proc)
      @vnp = name_proc
    end
  end


  module EdgesRouteModule
    def out_v(*filters, &block)
      VerticesRoute.new(self, filters, block, EdgeVertexPipe::Step::OUT_VERTEX)
    end

    def in_v(*filters, &block)
      VerticesRoute.new(self, filters, block, EdgeVertexPipe::Step::IN_VERTEX)
    end

    def both_v(*filters, &block)
      VerticesRoute.new(self, filters, block, EdgeVertexPipe::Step::BOTH_VERTICES)
    end

    def v(*filters)
      raise "Can't call vertices for EdgesRoute."
    end

    def e(*filters, &block)
      path = EdgesRoute.new(self, filters, block)
      path.pipe_class = nil
      path
    end

    def labels
      map { |e| e.get_label }
    end

    def result(name = nil)
      edge_ids = ids
      if edge_ids.count > 1
        g = graph
        r = EdgesRoute.new(proc { graph.load_edges(edge_ids) })
        r.graph = g
        r.pipe_class = nil
        r.info = "#{ name }:#{edge_ids.count}"
        r
      else
        graph.edge ids.first
      end
    end

    def to_h
      inject(Hash.new { |h,k| h[k]=[] }) do |h, edge|
        h[edge.out_vertex] << edge.in_vertex
        h
      end
    end

    protected

    # The filters and block this processes are the ones that are passed to the
    # initialize method, not the ones passed to in_v, out_v, etc...
    def filter_pipe(pipe, filters, block)
      labels = filters.select { |arg| arg.is_a? Symbol or arg.is_a? String }
      if labels.empty?
        super
      else
        label_pipe = LabelsFilterPipe.new
        label_pipe.set_labels labels
        label_pipe.set_starts pipe
        super(label_pipe, filters - labels, block)
      end
    end
  end

  module VerticesRouteModule
    def out_e(*filters, &block)
      EdgesRoute.new(self, filters, block, VertexEdgePipe::Step::OUT_EDGES)
    end

    def in_e(*filters, &block)
      EdgesRoute.new(self, filters, block, VertexEdgePipe::Step::IN_EDGES)
    end

    def both_e(*filters, &block)
      EdgesRoute.new(self, filters, block, VertexEdgePipe::Step::BOTH_EDGES)
    end

    def v(*filters, &block)
      path = VerticesRoute.new(self, filters, block)
      path.pipe_class = nil
      path
    end

    def e(*filters, &block)
      raise "Can't call edges for VerticesRoute."
    end

    def result(name = nil)
      v_ids = ids
      if v_ids.count > 1
        g = graph
        r = VerticesRoute.new(proc { graph.load_vertices(v_ids) })
        r.info = "#{ name }:#{v_ids.count}"
        r.graph = g
        r.pipe_class = nil
        r
      else
        graph.vertex v_ids.first
      end
    end

    def to(label, to_vertices)
      case to_vertices
      when Route
        raise "Must be from same graph" unless to_vertices.from_graph?(graph)
      when Enumerable, Iterator
        raise "Must be from same graph" unless to_vertices.first.from_graph?(graph)
      else
        raise "Must be from same graph" unless to_vertices.from_graph?(graph)
        to_vertices = [to_vertices]
      end
      map do |from_v|
        to_vertices.map do |to_v|
          graph.add_edge(nil, from_v, to_v, label) rescue nil
        end
      end
    end
  end

  class EdgesRoute
    include Route
    include RouteOperations
    include EdgesRouteModule

    def initialize(*args)
      @pipe_class = VertexEdgePipe
      initialize_path(*args)
    end
  end


  class VerticesRoute
    include Route
    include RouteOperations
    include VerticesRouteModule

    def initialize(*args)
      @pipe_class = EdgeVertexPipe
      initialize_path(*args)
    end
  end

  class VertexVariableRoute
    include Route
    include RouteOperations
    include VerticesRouteModule
    include VariableRouteModule
  end


  class EdgeVariableRoute
    include Route
    include RouteOperations
    include EdgesRouteModule
    include VariableRouteModule
  end



  module VertexMixin
    def inspect
      "#<#{ ["V[#{id}]", name].compact.join(' ') }>"
    end

    def name
      graph.vertex_name.call self if graph and graph.vertex_name
    end

    def delete!
      graph.remove_vertex self
    end
  end

  module EdgeMixin
    def inspect
      "#<E[#{id}]:#{ out_vertex.id }-#{ get_label }-#{ in_vertex.id }>"
    end

    def delete!
      graph.remove_edge self
    end
  end

  module ElementMixin
    def graph=(graph)
      @graph = graph
    end

    def graph
      @graph
    end

    def [](key)
      get_property(key.to_s)
    end

    def result(name = nil)
      self
    end

    def from_graph?(graph)
      if @graph
        @graph == graph
      elsif graph.raw_graph == raw_vertex.graph_database
        @graph = graph
        true
      end
    end

    def properties
      property_keys.inject({}) { |h, k| h[k] = get_property(k); h }
    end

    def name
      id
    end
  end

  class Neo4jVertex
    include VerticesRouteModule
    include ElementMixin
    include VertexMixin
  end

  class Neo4jEdge
    include EdgesRouteModule
    include ElementMixin
    include EdgeMixin
  end
end
