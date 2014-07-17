class Heroku::Command::Docker < Heroku::Command::Base
 
  # docker:build
  #
  # create docker image from heroku app
  #
  # requires local docker binary
  #
  # -b, --base  # override default base image
  # -t, --tag   # specify a tag for the image
  #
  def build
    stack = api.get_app(app).body["stack"]

    base = options[:base] || case stack
      when "bamboo-ree-1.8.7" then "ddollar/heroku-bamboo"
      when "bamboo-mri-1.9.2" then "ddollar/heroku-bamboo"
      else error("Unsupported stack: #{stack}")
    end

    tag = options[:tag] || app

    releases = get_v3("/apps/#{app}/releases")
    latest   = releases.sort_by { |r| r["version"] }.last
    slug     = get_v3("/apps/#{app}/slugs/#{latest["slug"]["id"]}")
    config   = api.get_config_vars(app).body

    env = env_minus_config(app)

    Dir.mktmpdir do |dir|
      write_databaseyml dir, config["DATABASE_URL"]
      write_dockerfile dir, base, slug["blob"]["url"], env
      build_image dir, tag
    end

    puts "Built image #{tag}"
  end

  # docker:run
  #
  # run a docker image using config from app
  #
  # requires local docker binary
  #
  # -i, --image  # specify an image
  #
  def run
    image = options[:image] || app
    config = api.get_config_vars(app).body

    Dir.mktmpdir do |dir|
      write_envfile dir, config
      system %{ docker run -it -P --env-file="#{dir}/.env" #{image} }
    end
  end

private

  def get_v3(uri)
    json_decode(heroku.get(uri, "Accept" => "application/vnd.heroku+json; version=3"))
  end

  def write_databaseyml(dir, database_url)
    uri = URI.parse(database_url)
    IO.write("#{dir}/database.yml", <<-DATABASEYML)
      ---
      production:
        encoding: unicode
        port: #{uri.port}
        username: #{uri.user}
        adapter: postgresql
        database: #{uri.path[1..-1]}
        host: #{uri.host}
        password: #{uri.password}
    DATABASEYML
  end

  def write_dockerfile(dir, base, url, env)
    envs = env.keys.sort.map { |key| "ENV #{key} #{env[key]}" }.join("\n")
    IO.write("#{dir}/Dockerfile", <<-DOCKERFILE)
      FROM #{base}
      RUN curl '#{url}' -o /slug.img
      RUN rm -rf /app
      RUN unsquashfs -d /app /slug.img
      RUN rm /app/log /app/tmp
      RUN mkdir /app/log /app/tmp
      WORKDIR /home/heroku_rack
      RUN curl -L http://cl.ly/2k1p1K0i032f/heroku_rack.tgz | tar xz
      ADD database.yml /app/config/database.yml
      #{envs}
      WORKDIR /app
      EXPOSE 5000
      CMD thin -p 5000 -e ${RACK_ENV:-production} start
    DOCKERFILE
  end

  def write_envfile(dir, config)
    File.open("#{dir}/.env", "w") do |f|
      config.keys.sort.each do |key|
        f.puts "#{key}=#{config[key]}"
      end
    end
  end

  def build_image(dir, tag)
    system "docker build -t #{tag} #{dir}"
  end

  def env_minus_config(app)
    data = api.post_ps(app, "env", :attach => true).body
    buffer = StringIO.new
    rendezvous = Heroku::Client::Rendezvous.new(:rendezvous_url => data["rendezvous_url"], :output => buffer)
    rendezvous.start
    env = buffer.string.split("\n").inject({}) do |ax, line|
      name, value = line.split("=", 2)
      ax.update name => value
    end
    for name, value in api.get_config_vars(app).body do
      env.delete name
    end
    env["PS"] = "docker.1"
    env
  end

end
