module Rummager

  def Rummager.fingerprint_obj ( source_object )
    content = nil
    if source_object.is_a?( String )
      content = source_object
      Digest::MD5.hexdigest( source_object )
    elsif source_object.is_a?( Dir )
      files = Dir["#{source_object.path}/**/*"].reject{ |f| File.directory?(f) }
      content = files.map{|f| File.read(f)}.join
    else
      raise ArgumentError, "Unhandled argument: #{source_object.to_s} is not a String or Dir"
    end
    Digest::MD5.hexdigest(content)
  end

end # Rummager