module Rummager

  def Rummager.fingerprint ( name )
      image_dir = File.join( Rake.application.original_dir, name )
      raise IOError, "Directory '#{image_dir}' does not exist!" if ! File::exist?( image_dir )
      files = Dir["#{image_dir}/**/*"].reject{ |f| File.directory?(f) }
      content = files.map{|f| File.read(f)}.join
      Digest::MD5.hexdigest(content)
  end

end # Rummager