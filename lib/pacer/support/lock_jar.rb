module LockJar
  # If Bundler constant is defined, assume we are running in a bundled environment and
  # register all Jarfiles
  def self.register_bundled_jarfiles
    if defined? Bundler
      Gem::Specification.each do |spec|
        jarfile = File.join(spec.full_gem_path, 'Jarfile')
        LockJar.register_jarfile(jarfile, spec) if File.exist? jarfile
      end
      true
    end
  end
end
