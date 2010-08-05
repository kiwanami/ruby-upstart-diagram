#!/usr/bin/ruby

# Upstart Diagram

#Author::    Masashi Sakurai (mailto:m.sakurai@kiwanami.net)
#Copyright:: Copyright (C) 2010 Masashi Sakurai 
#License::   Ruby's


require 'strscan'

init_dir = "/etc/init"

def log(msg)
  #puts msg
end

if $*.size > 0
  init_dir = $*[0]
end

class USEvent
  def initialize(from, name)
    @from = from
    @name = name
    @values = []
  end
  def add_value(v)
    @values << v
  end
  def to_s
    if @values.size == 0 
      " \"#{@from}\" -> \"#{@name}\";"
    else
      s = @values.join(" ")
      " \"#{@from}\" -> \"#{@name}\" [label = \"#{s}\"];"
    end
  end
end

class USDepend
  def initialize(from, name, event)
    @from = from
    @name = name
    @event = event
    @values = []
  end
  def add_value(v)
    @values << v
  end
  def to_s
    if @values.size == 0 
      " \"#{@from}\" -> \"#{@name}\" [label = \"#{@event}\"];"
    else
      s = @values.join(" ")
      " \"#{@from}\" -> \"#{@name}\" [label = \"#{@event} #{s}\"];"
    end
  end
end

class USEmit
  def initialize(from, name)
    @from = from
    @name = name
  end
  def to_s
    " \"#{@from}\" -> \"#{@name}\" [label = \"emit\"];"
  end
end

class USProcess
  def initialize(name)
    @name = name
  end
  def to_s
    return " \"#{@name}\" [shape = box];"
  end
end

def process_file(file)
  log "#FILE #{file}"
  name = File.basename(file,".conf")

  filestr = IO.read(file)
  scanner = StringScanner.new(filestr)

  return { 
    :process => [USProcess.new(name)],
    :starton => (process_starton(name,scanner) || []).flatten,
    :stopon => (process_stopon(name,scanner) || []).flatten,
    :emits => process_emits(name,scanner) || [] }
end

def process_starton(name,scanner)
  log "#==start on"
  ps = scanner.string.index(/^start on/)
  return nil unless ps 
  
  scanner.pos = ps
  scanner.scan(/start on\s+/)
  
  tree = []
  ret = process_term(name, scanner, tree)
  log "#RETURN -> #{tree}"
  return tree
end

def process_stopon(name,scanner)
  log "#==stop on"
  ps = scanner.string.index(/^stop on/)
  return nil unless ps 
  
  scanner.pos = ps
  scanner.scan(/stop on\s+/)
  
  tree = []
  ret = process_term(name, scanner, tree)
  log "#RETURN -> #{tree}"
  return tree

end

def process_emits(name,scanner)
  log "#==emits"
  lines = scanner.string.split("\n")
  ret = []
  lines.each {|i| 
    if /^emits\s+([a-z\-]+)/ =~ i
      emit = Regexp.last_match[1]
      ret << USEmit.new(name,emit)
    end
  }
  return ret
end

def process_term(name, scanner, tree)
  log "?TERM #{scanner.peek(10)}"
  (
   node_parentheses(name, scanner, tree) ||
   node_events(name, scanner, tree)
   )
end

def node_parentheses(name, scanner, tree)
  log "?PAREN"
  pos = scanner.pos
  ttree = []
  ret = (scanner.scan(/\(\s*/) &&
         process_term(name, scanner, ttree) &&
         scanner.scan(/\s*\)\s*/))
  if ret
    log "#PAREN -> #{ttree}"
    tree << ttree
  else
    scanner.pos = pos
  end
  return ret
end

def node_events(name, scanner, tree)
  log "?EVENTS"
  if ( node_depend(name, scanner, tree) ||
       node_event(name, scanner, tree))
    pos = scanner.pos
    if ( node_andor(name, scanner, tree) )
      log "#ANDOR -> #{tree}"
      process_term(name, scanner, tree)
    end
    return true
  else
    return false
  end
end

def node_depend(name, scanner, tree)
  log "?DEPEND"
  return nil unless scanner.scan(/(starting|started|stopping|stopped)\s+([a-z\-]+)/)
  event = scanner[1]
  from = scanner[2]
  log "#DEPEND #{event} #{from}"
  ev = USDepend.new(from,name,event)
  tree << ev
  process_key_values(name,scanner,tree,ev)
  return true
end

def node_event(name, scanner, tree)
  log "?EVENT"
  return nil unless scanner.scan(/([a-z\-]+)/)
  from = scanner[1]
  log "#EVENT #{from}"
  ev = USEvent.new(from,name)
  tree << ev
  process_key_values(name,scanner,tree,ev)
  return true
end

def process_key_values(name, scanner, tree, event)
  loop do
    pos = scanner.pos
    if scanner.scan(/\s*\n/)
      log "#NO KEY-VALUE TERMINATE"
      return true
    elsif node_andor(name,scanner,tree)
      log "#NO KEY-VALUE"
      scanner.pos = pos
      return true
    else
      log "?KEY-VALUE"
      kv = scanner.scan(/\s*([a-zA-Z0-9!=\[\]_]+)/)
      break unless kv
      log "#KEY-VALUE #{kv}"
      event.add_value(scanner[1])
    end
  end
end

def node_andor(name, scanner, tree)
  log "?ANDOR"
  return nil unless scanner.scan(/\s*(and|or)\s+/)
  andor = scanner[1]
  log "#ANDOR #{andor}"
  return true
end

entries = []

Dir.glob(init_dir+"/*.conf") {|i|
  entries << process_file(i)
}

# start on
str = entries.map{|i| (i[:process]+i[:starton]+i[:emits]).join("\n") }.join("\n")
print "digraph Upstart {
    graph [label=\"start on\", rankdir = LR, fontsize = 30, fontcolor = red];
    node [shape = \"ellipse\"];
    startup;

#{ str }

}\n\n"

# stop on
str = entries.map{|i| (i[:process]+i[:stopon]).join("\n") }.join("\n")
print "digraph Upstart {
    graph [label=\"stop on\", rankdir = LR, fontsize = 30, fontcolor = red];
    node [shape = \"ellipse\"];

#{ str }

}\n"
