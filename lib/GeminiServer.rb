
require "socket"
require "openssl"
require "uri"

module GeminiPage
  
  # Indexes a path of the file sysem (with folders) and creates corresponding
  # handlers. There is no caching.
  # All files which do not have a mimetype with text/ are read binary.
  #
  # @param serv [GeminiServer] The server object on which the handlers should be
  # registered.
  # @param dir_path [String] Path to be indexed.
  # @param prefix [String] Prefix on the server.
  # @param extensions [Hash] List of file extensions and corresponding mimetypes.
  # @param default [String] Default mimetype
  # @param file_prefix [String] Internal use. Path from the file system which
  # should not be used as a prefix on the server.
  # @example Indexes the downloads folder of the user "user" and makes the files
  # available under "/computer/Downloads/".
  #   GeminiPage.index_dir serv, "/home/user/Downloads/", "/computer/Downloads/"
  def self.index_dir serv, dir_path, prefix = "/", extensions = {"gmi" => "text/gemini"}, default = "application/octet-stream", file_prefix = nil
    file_prefix = dir_path if ! file_prefix
    
    Dir["#{dir_path}/*"].each { |entry|
      puts entry
      if File.file?(entry) && File.readable?(entry)
        serv_path = entry.delete_prefix file_prefix
        serv_path.delete_prefix! "/"
        serv.register_handler("#{prefix}#{serv_path}", ->(conn, cert, input) {
            extension = serv_path.split(".")[-1]
            mimetype = extensions[extension]
            mimetype = default if ! mimetype
            conn.print "20 #{mimetype}\r\n"
            mode = "r"
            if ! mimetype.start_with? "text/"
              mode += "b"
            end
            fil = File.open(entry, mode)
            IO::copy_stream(fil, conn)
        })
      else File.directory?(entry)
        index_dir serv, entry, prefix, extensions, default, file_prefix
      end
    }
  end
  
  # Creates a static page without dynamic (therefore interactive) content.
  #
  # @param code [String] The status code which will be returned.
  # @param meta [String] Meta information. For example, the mimetype for status 20.
  # @param content [String] The content from which the page is created.
  # @return [Proc]
  # @example A simple page in Gemini format, which has "Hello World!" as its headline.
  #   GeminiPage.static_page("20", "text/gemini; lang=en", "# Hello World!")
  def self.static_page code, meta, content = nil
    page = "#{code} #{meta}\r\n"
    #content.insert(content.index("\n"), "\r")
    page += content.to_s
    
    return ->(conn, cert, input) {conn.print page}
  end
  
  # Requests an input from the client and calls the function after successful input.
  #
  # @param func [Proc] Function which is called.
  # @param input_prompt [String] Prompt to be sent to the client.
  # @param secret [String] True if the input contains sensitive data such as a
  # password, false otherwise.
  # @return [Proc]
  # @example A simple page in Gemini format, which has "Hello World!" as its headline.
  #   GeminiPage.require_input(->(conn, cert, input) {
  #   conn.print "20 text/gemini\r\n"
  #   conn.print "# Input test\n"
  #   conn.print "Your input is #{input}"
  #   }, "Some input", true)
  def self.require_input func, input_prompt, secret = false
    return ->(conn, cert, input) {
      if input == ""
        code = "10"
        code = "11" if secret
        conn.print "#{code} #{input_prompt}\r\n"
      else
        func.(conn, cert, input)
      end
    }
  end
  
  # Creates a temporary redirect.
  #
  # @param new_location [String]
  # @return [Proc]
  # @example
  #   GeminiPage.redirect_permanent("/new_location")
  def self.redirect_temporary new_location
    return ->(conn, cert, input) {
      conn.print "30 #{new_location}\r\n"
    }
  end
  
  # Creates a permanent redirect.
  #
  # @param new_location [String]
  # @return [Proc]
  # @example
  #   GeminiPage.redirect_permanent("/new_location")
  def self.redirect_permanent new_location
    return ->(conn, cert, input) {
      conn.print "31 #{new_location}\r\n"
    }
  end
end

# @example A test server
#   cert = OpenSSL::X509::Certificate.new File.read "cert.crt"
#   key  = OpenSSL::PKey::RSA.new File.read "priv.pem"
#   serv = GeminiServer.new cert, key
#   
#   users = {}
#   
#   serv.register_handler "/", GeminiPage.static_page("20", "text/gemini; lang=en", <<CONTENT)
#   # Hello to my Ruby Gemini server
#   
#   This is the startpage.
#   You can take a look at /cert to test the certificate function of the server
#   or at /input and /inputpw to test the input function of this server :-)
#   => /cert
#   => /input
#   => /inputpw
#   => /redirect
#   => /test2
#   
#   Hope it works!
#   CONTENT
#   #   .register_handler "", GeminiPage.redirect_permanent("/")
#   # or
#   # serv.copy_handler("/", "")
#   
#   serv.register_handler "/cert", ->(conn, cert, input) {
#     if conn.peer_cert == nil
#       conn.print "60 Require certificate\r\n"
#       return
#     end
#     
#     conn.print "20 text/gemini\r\n"
#     conn.puts "# Certificate test\n"
#     conn.puts "Certificate subject and issuer are equal.\n" if cert.subject == cert.issuer
#     conn.puts "Serialnumber: #{cert.serial.to_s}\n"
#     conn.puts "## Subject\n"
#     cert.subject.to_a.each { |entry|
#       conn.puts "* #{entry[0]} : #{entry[1]}\n"
#     }
#     conn.puts "## Issuer\n"
#     cert.issuer.to_a.each { |entry|
#       conn.puts "* #{entry[0]} : #{entry[1]}\n"
#     }
#     
#     if ! users[cert.subject.to_s]
#       users[cert.subject.to_s] = cert.public_key
#     end
#     
#     if cert.verify users[cert.subject.to_s]
#       conn.puts "You are authenticated as #{cert.subject.to_s}"
#     else
#       conn.puts "You are not authenticated as #{cert.subject.to_s}"
#     end
#   }
#   
#   serv.register_handler "/input", GeminiPage.require_input(->(conn, cert, input) {
#     conn.print "20 text/gemini\r\n"
#     conn.print "# Input test\n"
#     conn.print "Your input is #{input}"
#   }, "Some input", true)
#   
#   serv.register_handler "/inputpw", GeminiPage.require_input(->(conn, cert, input) {
#     conn.print "20 text/gemini\r\n"
#     conn.print "# Input test\n"
#     conn.print "Your input is #{input}"
#   }, "Some secret input", true)
#   
#   serv.register_handler "/test2", ->(conn, cert, input) {
#     conn.print "20 \r\n"
#     conn.print "Hello World!"
#   }
#   
#   serv.register_handler "/redirect", GeminiPage.redirect_permanent("/")
#   
#   serv.start
#   
#   puts "Listen..."
#   serv.listen true
class GeminiServer
  
  attr_accessor :not_found_page
  
  # Creates a Gemini Server
  #
  # @param cert [OpenSSL::X509::Certificate]
  # @param key [OpenSSL::PKey::PKey]
  # @example
  #   cert = OpenSSL::X509::Certificate.new File.read "cert.crt"
  #   key  = OpenSSL::PKey::RSA.new File.read "priv.pem"
  #   serv = GeminiServer.new cert, key
  def initialize cert, key
    @context = OpenSSL::SSL::SSLContext.new
    # Require min tls version (spec 4.1)
    @context.min_version = :TLS1_2
    @context.add_certificate cert, key
    # Enable client certificates (spec 4.3)
    @context.verify_mode = OpenSSL::SSL::VERIFY_PEER
    # Ignore invalid (e. g. self-signed) certificates
    @context.verify_callback = ->(passed, cert) { return true }
    @handlers = {}
    @not_found_page = GeminiPage.static_page("51", "Not found")
  end
  
  # Starts the server. However, the server does not yet respond to requests.
  #
  # @param host [String]
  # @param port [Integer]
  # @example
  #   serv.start
  def start host = "localhost", port = 1965
    serv = TCPServer.new host, port
    @secure = OpenSSL::SSL::SSLServer.new(serv, @context)
  end
  
  # Starts the server. However, the server does not yet respond to requests.
  # 
  # Registers a handler for a specific path. The handler is a function (Proc),
  # which gets three parameters:
  # * The current connection to the client. Through this the function can return
  # content to the client. Can be handled similar to a stream.
  # * The (if available) certificate sent by the client.
  # * The input (if any) sent by the client.
  #
  # @param path [String]
  # @param func [Proc]
  # @example
  #   serv.register_handler "/", ->(conn, cert, input) {
  #     conn.print "20 \r\n"
  #     conn.print "Hello World!"
  #   }
  def register_handler path, func
    @handlers[path] = func
  end
  
  # Copies a handler for another path. If the original handler is edited, the
  # new one is not edited.
  #
  # @param path [String]
  # @param copy_path [String]
  # @example
  #   serv.copy_handler("/", "")
  def copy_handler path, copy_path
    @handlers[linked_path] = @handlers[path]
  end
  
  # Removes a handler
  #
  # @param path [String]
  def delete_handler path
    @handlers.delete path
  end
  
  # Enables the server so that it responds to requests. This blocks the rest of
  # the program.
  #
  # @param log [TrueClass, FalseClass] If enabled, successful requests from
  # clients are output.
  # @example
  #   serv.listen
  def listen log = false
    loop do
      begin
        Thread.new(@secure.accept) do |conn|
          begin
            uri = URI(conn.gets.chomp)

            if uri.scheme != "gemini"
              conn.print "59 Unknown scheme: #{uri.scheme}\r\n"
            end

            if @handlers[uri.path]
              page = @handlers[uri.path].(conn, conn.peer_cert, URI.decode_www_form_component(uri.query.to_s))
              puts "#{conn.io.peeraddr(false)[-1]} request #{uri.path}"
            else
              page = @not_found_page.(conn, conn.peer_cert, URI.decode_www_form_component(uri.query.to_s))
            end
            
            conn.flush
            conn.close
          rescue
            $stderr.puts $!
          end
        end
      rescue
        $stderr.puts $!
      end
    end
  end
  
end