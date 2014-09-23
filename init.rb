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

    base = options[:base] || case stack.split("-").first
      when "bamboo" then "ddollar/heroku-bamboo"
      when "cedar"  then "ddollar/heroku-cedar"
      else error("Unsupported stack: #{stack}")
    end

    tag = options[:tag] || app

    releases = get_v3("/apps/#{app}/releases")
    latest   = releases.sort_by { |r| r["version"] }.last
    slug     = get_v3("/apps/#{app}/slugs/#{latest["slug"]["id"]}")

    env = env_minus_config(app)

    Dir.mktmpdir do |dir|
      write_database_yml dir
      write_dockerfile dir, base, slug["blob"]["url"], env, web_command(app)
      build_image dir, tag
    end

    puts "Built image #{tag}"
  end

  # docker:context TARFILE
  #
  # create docker context from heroku app
  #
  # requires local docker binary
  #
  # -b, --base  # override default base image
  #
  def context
    unless tarfile = shift_argument
      error("Usage: heroku docker:context TARFILE")
    end

    stack = api.get_app(app).body["stack"]

    base = options[:base] || case stack.split("-").first
      when "bamboo" then "ddollar/heroku-bamboo"
      when "cedar"  then "ddollar/heroku-cedar"
      else error("Unsupported stack: #{stack}")
    end

    tag = options[:tag] || app

    releases = get_v3("/apps/#{app}/releases")
    latest   = releases.sort_by { |r| r["version"] }.last
    slug     = get_v3("/apps/#{app}/slugs/#{latest["slug"]["id"]}")

    env = env_minus_config(app)

    Dir.mktmpdir do |dir|
      write_database_yml dir
      write_dockerfile dir, base, slug["blob"]["url"], env, web_command(app)

      Dir.chdir(dir) do
        system %{ tar cf #{tarfile} . }
      end
    end

    puts "Wrote context to #{tarfile}"
  end

  # docker:run [COMMAND]
  #
  # run a docker image using config from app
  #
  # requires local docker binary
  #
  # -d, --detach  # run the docker container in the background
  # -i, --image   # specify an image
  #
  def run
    image = options[:image] || app
    config = api.get_config_vars(app).body

    Dir.mktmpdir do |dir|
      write_envfile dir, config
      docker_args = [ "-P", %{--env-file="#{dir}/.env"}, "-u daemon" ]
      docker_args.push (options[:detach] ? "-d" : "-it")
      system %{ docker run #{docker_args.join(" ")} #{image} #{args.join(" ")} }
    end
  end

private

  def get_v3(uri)
    json_decode(heroku.get(uri, "Accept" => "application/vnd.heroku+json; version=3"))
  end

  def write_database_yml(dir)
    IO.write("#{dir}/database.yml", <<-DATABASEYML)
      <%
      require 'cgi'
      require 'uri'
      begin
        uri = URI.parse(ENV["DATABASE_URL"])
      rescue URI::InvalidURIError
        raise "Invalid DATABASE_URL"
      end
      raise "No RACK_ENV or RAILS_ENV found" unless ENV["RAILS_ENV"] || ENV["RACK_ENV"]
      def attribute(name, value, force_string = false)
        if value
          value_string =
            if force_string
              '"' + value + '"'
            else
              value
            end
          "\#{name}: \#{value_string}"
        else
          ""
        end
      end
      adapter = uri.scheme
      adapter = "postgresql" if adapter == "postgres"
      database = (uri.path || "").split("/")[1]
      username = uri.user
      password = uri.password
      host = uri.host
      port = uri.port
      params = CGI.parse(uri.query || "")
      %>
      <%= ENV["RAILS_ENV"] || ENV["RACK_ENV"] %>:
        <%= attribute "adapter",  adapter %>
        <%= attribute "database", database %>
        <%= attribute "username", username %>
        <%= attribute "password", password, true %>
        <%= attribute "host",     host %>
        <%= attribute "port",     port %>
      <% params.each do |key, value| %>
        <%= key %>: <%= value.first %>
      <% end %>
    DATABASEYML
  end

  def web_command(app)
    formation = get_v3("/apps/#{app}/formation")
    web = formation.detect { |f| f["type"] == "web" }
    return "bash" unless web
    web["command"]
  end

  def write_dockerfile(dir, base, url, env, cmd)
    envs = env.keys.sort.map { |key| "ENV #{key} #{env[key]}" }.join("\n")
    IO.write("#{dir}/Dockerfile", <<-DOCKERFILE.split("\n").map { |l| l.strip }.join("\n"))
      FROM #{base}
      RUN rm -rf /app
      RUN curl '#{url}' -o /slug.img
      RUN (unsquashfs -d /app /slug.img || (cd / && mkdir /app && tar -xzf /slug.img)) && rm -f /app/log /app/tmp && mkdir /app/log /app/tmp &&  chown -R daemon:daemon /app && chmod -R go+r /app && find /app -type d | xargs chmod go+x
      ADD database.yml /app/config/database.yml
      #{envs}
      WORKDIR /app
      EXPOSE 5000
      CMD #{cmd}
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
      env.delete name unless name == "PATH"
    end
    env["PS"] = "docker.1"
    env["HEROKU_RACK"] = "/app/config.ru" if env["HEROKU_RACK"]
    env["PORT"] = "5000"
    env.delete "_"
    env.delete "DYNO"
    env
  end

end
