#!/usr/bin/ruby

require 'optparse'
require 'bio'
require 'net/http'

$database = {
  "ApESTassA3" => "/DB/local/ApisumEST/assemble_A3/blastdb/ApisumFullWB_plus_ApsAllPub.fas.cap.contigs",
  "DmelP" => "/DB/KEGG/blastdb/d.melanogaster.pep",
  "DmelN" => "/DB/KEGG/blastdb/d.melanogaster.nuc",
}

class EUtils

  SERVER_DEFAULT = "www.ncbi.nlm.nih.gov"
  PATH_DEFAULT   = "/entrez/eutils"

  def self.program
    raise "should be implemeted in child class"
  end

  def initialize()
    @program = self.class.program
    @esearch_uri = "http://#{EUtils::SERVER_DEFAULT}#{EUtils::PATH_DEFAULT}/#{@program}"
    uri = URI.parse(@esearch_uri)
    @host = uri.host
    @path = uri.path
  end

  def build_query(param) # param: Hash
    str = param.collect{|k, v| "#{k}=#{v}"}.join("&")
    str = str.gsub(/ /, '+')
    URI.escape(str)
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

class ESearch < EUtils

  def self.program
    "esearch.fcgi?"
  end

end

class EFetch < EUtils

  def self.program
    "efetch.fcgi?"
  end

end

class SearchBase
  def initialize
  end
  def get_fasta(query)
    raise
  end
end

class NCBISearch < SearchBase
  def initialize(db = "nucleotide")
    @db = db
  end

  def get_fasta(query)
    es =  ESearch.new
    res = es.exec("db"=> @db, "term"=>query)
    id = %r{<Id>(.+?)</Id>}.match(res)[1].strip
    raise unless id
    ef = EFetch.new
    res = ef.exec("db"=> @db, "id"=>id, "rettype"=>"fasta")
    result = Bio::FastaFormat.new(res)
    return result
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

puts seq.to_fasta(result.definition, 60)
