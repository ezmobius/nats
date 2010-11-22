#--
#
# Sublist implementation for a publish-subscribe system.
# This container class holds subscriptions and matches 
# candidate subjects to those subscriptions.
# Certain wildcards are supported for subscriptions. 
# '*' will match any given token at any level.
# '>' will match all subsequent tokens.
#--
# See included test for example usage:
##

require File.dirname(__FILE__) + '/lru_hash'

class Sublist #:nodoc:
  PWC = '*'.freeze
  FWC = '>'.freeze
  CACHE_SIZE = 4096
  
  attr_reader :count

  SublistNode  = Struct.new(:leaf_nodes, :next_level)
  SublistLevel = Struct.new(:nodes, :pwc, :fwc)
  
  def initialize(options = {})
    @count = 0
    @results = []
    @root = SublistLevel.new({})
    @cache = {}
  end

  # Ruby is a great language to make selective trade offs of space versus time.
  # We do that here with a low tech front end cache. The cache holds results
  # until it is exhausted or if the instance inserts or removes a subscription.
  # The assumption is that the cache is best suited for high speed matching,
  # and that once it is cleared out it will naturally fill with the high speed
  # matches. This can obviously be improved with a smarter LRU structure that
  # does not need to completely go away when a remove happens..
  #
  # front end caching is on by default, but we can turn it off here if needed
  
  def disable_cache; @cache = nil; end
  def enable_cache;  @cache ||= {};  end
  def clear_cache; @cache = {} if @cache; end

  # Insert a subscriber into the sublist for the given subject.
  def insert(subject, subscriber)
    # TODO - validate subject as correct.
    level, tokens = @root, subject.split('.')
    for token in tokens
      # This is slightly slower than direct if statements, but looks cleaner.
      case token
        when FWC then node = (level.fwc || (level.fwc = SublistNode.new([])))
        when PWC then node = (level.pwc || (level.pwc = SublistNode.new([])))
        else node  = ((level.nodes[token]) || (level.nodes[token] = SublistNode.new([])))
      end
      level = (node.next_level || (node.next_level = SublistLevel.new({})))
    end
    node.leaf_nodes.push(subscriber)
    @count += 1
  end

  # Remove a given subscriber from the sublist for the given subject.
  def remove(subject, subscriber)
    # TODO: implement (remember cache and count cleanup if applicable)
    # Reference counts and GC for long empty tree.
    level, tokens = @root, subject.split('.')
    for token in tokens
      next unless level
      case token
        when FWC then node = level.fwc
        when PWC then node = level.pwc
        else node  = level.nodes[token]
      end
      level = node.next_level      
    end
    # This could be expensize if a large number of subscribers exist.
    node.leaf_nodes.delete(subscriber) if (node && node.leaf_nodes) 
  end
  
  # Match a subject to all subscribers, return the array of matches.
  def match(subject)
    if (@cache && (node = @cache[subject]))
      return node
    end   
    tokens = subject.split('.')
    @results.clear
    matchAll(@root, tokens)
    # FIXME: This is too low tech, will revisit when needed.
    if @cache
      @cache[subject] = Array.new(@results).freeze # Avoid tampering of copy
    end
    @results
  end

  private
  
  def matchAll(level, tokens)
    node, pwc = nil, nil # Define for scope
    i, ts = 0, tokens.size
    while (i < ts) do
      return if level == nil
      # Handle a full wildcard here by adding all of the subscribers.
      @results.concat(level.fwc.leaf_nodes) if level.fwc      
      # Handle an internal partial wildcard by branching recursively
      lpwc = level.pwc
      matchAll(lpwc.next_level, tokens[i+1, ts]) if lpwc
      node, pwc = level.nodes[tokens[i]], lpwc
      #level = node.next_level if node
      level = node ? node.next_level : nil    
      i += 1
    end
    @results.concat(pwc.leaf_nodes) if pwc    
    @results.concat(node.leaf_nodes) if node
  end  

end
