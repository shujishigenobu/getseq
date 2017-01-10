#!/usr/bin/ruby

require 'optparse'
require 'bio'
require 'open-uri'


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
    ef = EFetch.new
    res = ef.exec("db"=> @db, "id"=>query, "rettype"=>"gb")
    return res
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
  dbfile = opt[:db]
  engine = FastaFileSearch.new(dbfile)
end

case opt[:format]
when "genbank", "gb"
  result = engine.get_genbank(query)
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


