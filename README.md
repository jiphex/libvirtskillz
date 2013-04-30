# libvirtskillz

Just a few patches to make the ruby libvirt API a bit less crap, with a view to
allowing someone to write simple snapshot-based backup scripts.

Makes the following possible:

    Libvirt::open.domains.each do |d|
      # Libvirt::Connection#domains is a list of domain objects, instead of IDs
      d.create_snapshot do |s|
        # With a block, creates snapshot and deletes it when the block is done
        puts s.backing_store # details about each disk and where it's stored

        # Takes a backup of a snapshot of every disk of this domain
        s.qemu_img_backup_commands("/var/backups/").each do{|s|system s}
        # Backups will be (e.g) /var/backups/webvm-hda.qcow
      end
    end

Use fpm to create a debian package with `make'.


