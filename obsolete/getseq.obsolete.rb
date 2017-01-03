#!/usr/bin/ruby

require 'optparse'
require 'bio'
#require 'net/http'
require 'open-uri'

$database = {
#  "ApESTassA3" => "/DB/local/ApisumEST/assemble_A3/blastdb/ApisumFullWB_plus_ApsAllPub.fas.cap.contigs",
#  "DmelP" => "/DB/KEGG/blastdb/d.melanogaster.pep",
#  "DmelN" => "/DB/KEGG/blastdb/d.melanogaster.nuc",
}

class EUtils

  HOST = "eutils.ncbi.nlm.nih.gov"
#  PATH_BASE   = "/entrez/eutils"

  def self.program
    raise "should be implemeted in child class"
  end

  def initialize()
    @program = self.class.program
    @host = HOST
    @path = PATH
  end

  def build_query(param) # param: Hash
    str = param.collect{|k, v| "#{k}=#{v}"}.join("&")
    str = str.gsub(/ /, '+')
    URI.escape(str)
  end

  def build_url(param={})
    p = {}
    p.update(param)
    query_str = build_query(p)
    newuri = URI::HTTPS.build({:host => host, :path=> PATH, :query => query})
  end

  def exec(param={})
    p = {}
    p.update(param)
    query_str = build_query(p)
    path = "#{@path}"
    path << "?" << query_str
    result = Net::HTTP.get(@host, path)
  end

end

#class ESearch < EUtils
#
#  def self.program
#    "esearch.fcgi?"
#  end
#
#end

class EFetch 

  HOST = "eutils.ncbi.nlm.nih.gov"
  PATH = "/entrez/eutils/efetch.fcgi/"

  def initialize()
    @host = HOST
    @path = PATH
  end

  def build_uri(query) # query as Hash
    q = query.collect{|k, v| "#{k}=#{v}"}.join("&")
    q = q.gsub(/ /, '+')
    q = URI.escape(q)
    uri = URI::HTTPS.build({:host => @host, :path=> @path, :query => q})
  end

  def exec(param={}) # param as hash
    uri = build_uri(param)
    res = open(uri)
    code, message = res.status # res.status => ["200", "OK"]

    if code == '200'
      return result = res.read
    else
      puts "Error #{code} #{message}"
      raise
    end
  end


end


class NCBISearch

  def initialize(db = "nucleotide")
    @db = db
  end

  def get_fasta(query)
    ef = EFetch.new
    res = ef.exec("db"=> @db, "id"=>query, "rettype"=>"fasta")
    fasta = Bio::FastaFormat.new(res)
  end

  def get_genbank(query)
    es =  ESearch.new
    res = es.exec("db"=> @db, "term"=>query)
    id = %r{<Id>(.+?)</Id>}.match(res)[1].strip
    raise unless id
    ef = EFetch.new
    res = ef.exec("db"=> @db, "id"=>id, "rettype"=>"gb")
    return res
  end

  def get_gi_list(query)
    es = ESearch.new
    res = es.exec("db" => @db, "term" => query, "retmax" => 100000)
    ids = res.scan(%r{<Id>(\d+)</Id>})
    totalcount = %r{<Count>(\d+)</Count>}.match(res)[1].to_i
    raise if totalcount > 100000
    ## ToDo
    ## add function to retrieve big list more than 100000 (max retrieval is limited to 100000 at NCBI)
    return ids
  end

end

class FastaFileSearch
  def initialize(file)
    @dbfile = file
  end

  def get_fasta(query)
    result = nil
    Bio::FlatFile.open(@dbfile).each do |fa|
      id = fa.definition.split[0]
      if id == query
        result = fa 
        break
      end
    end
    return result
  end
end

class BlastDBSearch

  def initialize(path)
    @dbfile = path
    @db = Bio::Blast::Fastacmd.new(path)
  end

  def get_fasta(query)
    @db.fetch(query).first
  end

end

op = OptionParser.new
opt = {}
op.on("-d", "--database DB", String){|v| opt[:db] = v}
op.on("-L", "--location LOCATION", String){|v| opt[:location] = v}
op.on("-r", "--reverse"){ opt[:reverse] = true}
op.on("-m", "--format FORMAT", String){|v| opt[:format] = v}
op.on("-u", "--upcase"){opt[:upcase] = true}

rest = op.parse(ARGV)
query = rest.shift.strip

result = nil
if /^ncbi:n/.match(opt[:db])
  engine = NCBISearch.new("nucleotide")
elsif /^ncbi:p/.match(opt[:db])
  engine = NCBISearch.new("protein")
elsif /blast/.match(opt[:db])
  engine = BlastDBSearch.new(opt[:db])
else
  dbfile = ($database[opt[:db]] || opt[:db])
  engine = FastaFileSearch.new(dbfile)
end

case opt[:format]
when "genbank", "gb"
  result = engine.get_genbank(query)
  puts result
when "gilist"
  result = engine.get_gi_list(query)
  puts result
else
  ##fasta
  result = engine.get_fasta(query)
  seq = Bio::Sequence.auto(result.seq)

  if opt[:location]
    seq = seq.splice(opt[:location])
  else
    seq
  end
  
  if opt[:reverse]
    seq = seq.reverse_complement
  end
  seq = seq.upcase if opt[:upcase]
  puts seq.to_fasta(result.definition, 60)
end


if __FILE__ == $0

end
