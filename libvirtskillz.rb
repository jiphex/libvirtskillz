#!/usr/bin/ruby

## Example:
# require 'libvirtskillz'
# Libvirt::open.domains.each do |dom|
#   dom.create_snapshot "Backup" do |s|
#    s.qemu_img_export_commands("/var/tmp").map{|a|system(a)}
#   end
# end

require 'libvirt'
require 'builder'
require 'nokogiri'

class Libvirt::Connect
  def domains
  	ld = self.list_domains
  	ld.map do |a|
  	  self.lookup_domain_by_id a
	end
  end
end

class Libvirt::Domain
  def create_snapshot(sdesc=nil)
  	builder = Builder::XmlMarkup.new
  	snapshot_xml = builder.domainsnapshot do |ds|
  	  if sdesc
  	  	ds.description(sdesc)
	  end
	end
	snap = self.snapshot_create_xml(snapshot_xml)
	if block_given?
	  yield snap
	  snap.delete
	else
	  return snap
	end
  end
end

class Libvirt::Domain::Snapshot
  def domain_uuid
  	noko_details.xpath("/domainsnapshot/domain/uuid").text.strip
  end

  def domain_name
  	noko_details.xpath("/domainsnapshot/domain/name").text.strip
  end

  def method_missing(meth,*args,&block)
  	m = noko_details.xpath("/domainsnapshot/#{meth}")
  	if m.length > 0
  	  m.first.text
	else
	  super
	end
  end

  def backing_store
  	bs = {}
	noko_details.xpath('/domainsnapshot/domain/devices/disk').map do |ddsk|
	  next if ddsk.xpath('@device').text != "disk"
	  next if ddsk.xpath('@snapshot').text == "external"
	  sf = ddsk.xpath('source/@file').text
	  td = ddsk.xpath('target/@dev').text
	  bs[td] = sf
	end
	bs
  end

  def qemu_img_export_commands(opath,cmd='qemu-img',compressed=true)
  	unless File.directory?(opath)
  	  puts "Not a directory: #{opath}"
	else
	  backing_store.map do |dev,file|
	  	partname = "backup-#{domain_name}-#{dev}-#{creationTime}.qcow"
	  	partpath = File.join(opath,partname)
	  	if File.exists?(partpath)
	  	  STDERR.puts "File exists: #{partpath}"
		else
		  "#{cmd} convert #{compressed ? "-O qcow2 -c ":" "}-s #{name} #{file} #{partpath}"
		end
	  end.reject{|a|a.nil?}
	end
  end

  private

  def noko_details
  	Nokogiri::XML(self.xml_desc)
  end
end

