#!/usr/bin/ruby

## Example:
# require 'libvirtskillz'
# Libvirt::open.domains.each do |dom|
#   dom.create_snapshot "Backup" do |s|
#    s.qemu_img_export_commands("/var/tmp").map{|a|system(a)}
#   end
# end

require 'libvirt'
require 'nokogiri'

# Monkey patches to the Libvirt::Connect class
class Libvirt::Connect

  # The libvirt API only contains methods for retrieving a list of Domain
  # names or IDs. This provides Libvirt::Connect#domains which returns a list of
  # Domain objects instead.
  #
  # As the result is just an Array, you can use Ruby's standard Array methods to
  # filter and modify the results, for example:
  #
  #  Libvirt::open.domains.find_all{|a|a.name=~/^windows/}
  def domains
  	active_domains = self.list_domains.map do |a|
  	  self.lookup_domain_by_id(a)
	end
	inactive_domains = self.list_defined_domains.map do |a|
	  self.lookup_domain_by_name(a)
	end
	(active_domains+inactive_domains).uniq
  end
end

# Monkey patches to the Libvirt::Domain class
class Libvirt::Domain

  states = {
      Libvirt::Domain::NOSTATE => ["no state"],
      Libvirt::Domain::RUNNING => ["running"],
      Libvirt::Domain::BLOCKED => ["blocked"],
      Libvirt::Domain::SHUTDOWN => ["shutdown"],
      Libvirt::Domain::SHUTOFF => ["shutoff", {
            Libvirt::Domain::DOMAIN_SHUTOFF_CRASHED => "Crashed",
            Libvirt::Domain::DOMAIN_SHUTOFF_DESTROYED => "Destroyed",
            Libvirt::Domain::DOMAIN_SHUTOFF_FAILED => "Failed",
            Libvirt::Domain::DOMAIN_SHUTOFF_FROM_SNAPSHOT => "From snapshot",
            Libvirt::Domain::DOMAIN_SHUTOFF_MIGRATED => "Migrated",
            Libvirt::Domain::DOMAIN_SHUTOFF_SAVED => "Saved",
            Libvirt::Domain::DOMAIN_SHUTOFF_SHUTDOWN => "Shutdown",
            Libvirt::Domain::DOMAIN_SHUTOFF_UNKNOWN => "Unknown",
      }],
      Libvirt::Domain::CRASHED => ["crashed"],
      #Libvirt::Domain::PMSUSPENDED => ["pmsuspended"],
      #Libvirt::Domain::LAST => ["last"]
  }


  # Call [virDomainCurrentSnapshot][1] to create a snapshot using the Libvirt API.
  # Please note that this will not work if the Domain uses LVM as a backing
  # store, and you'll need to use {#create_lvm_snapshot} instead.
  #
  # [1]:http://www.libvirt.org/html/libvirt-libvirt.html#virDomainCurrentSnapshot
  def create_snapshot
	snap = self.snapshot_create_xml("<domainsnapshot/>")
	if block_given?
	  yield snap
	  snap.delete
	else
	  return snap
	end
  end


  # Runs the commands necessary to create LVM snapshots of each of the disks of
  # the target Domain. This should result in a snapshot per LV, each named:
  # "srcdomname-volname-snap-timestamp". Returns a hash e.g {"vdb"=>"/dev/mapper..snap"}
  def create_lvm_snapshot
    tsnap = disks.map do |tgt,vol|
      snap_name = "#{name}-#{tgt}-snap-#{Time.now.to_i}"
      puts "lvcreate -n #{snap_name} -s #{vol} -L2G"
      if(system("lvcreate -n #{snap_name} -s #{vol} -L2G"))
        [tgt,File.join(File.dirname(vol),snap_name)]
      else
        nil
      end
    end.reject{|a|a.nil?}
    return Hash[tsnap]
  end

  # Enumerates the disks for this domain.
  #
  # Ignores disks which would not be snapshotted (snapshot=external)
  def disks
  	bs = {}
	noko_details.xpath('/domain/devices/disk').map do |ddsk|
	  next if ddsk.xpath('@device').text != "disk"
	  next if ddsk.xpath('@snapshot').text == "external"
	  sf = ddsk.xpath('source/@dev','source/@file').text
	  td = ddsk.xpath('target/@dev').text
	  bs[td] = sf
	end
	bs
  end

  private

  def noko_details
      Nokogiri::XML(self.xml_desc)
  end
end

# Monkey patches to the Libvirt::Domain::Snapshot class
class Libvirt::Domain::Snapshot

  def domain_uuid
  	noko_details.xpath("/domainsnapshot/domain/uuid").text.strip
  end

  def domain_name
  	noko_details.xpath("/domainsnapshot/domain/name").text.strip
  end

  # Convenience method to quickly access properties of this {Snapshot}
  def method_missing(meth,*args,&block)
  	m = noko_details.xpath("/domainsnapshot/#{meth}")
  	if m.length > 0
  	  m.first.text
	else
	  super
	end
  end

  # Returns the underlying block device for this snapshot.
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

  # Provides the qemu-img commands to export this snapshot to a different file.
  #
  # This assumes that you've got a VM using qcow[2] as it's disk, with a
  # snapshot taken using the {Libvirt::Domain#create_snapshot} method which you
  # want to extract to a new file.
  #
  # Doesn't actually runs the commands, it's assumed you'll do something like
  # this:
  #
  #   Libvirt::open.domains.first do |dom|
  #     dom.create_snapshot do |snap|
  #       snap.qemu_img_export_command("/var/tmp").each{|s|system s}
  #     end
  #   end
  #
  # @param opath [String] the directory intended to store the resulting files
  # @param cmd [String] the path/command to qemu-img
  # @param compressed [Boolean] whether to specify the qemu-img "compressed" flag
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

