require 'time'

module Pushy
  class Client
    attr_accessor :monitor
    attr_accessor :ctx
    attr_accessor :out_address
    attr_accessor :in_address
    attr_accessor :interval
    attr_accessor :client_private_key
    attr_accessor :server_public_key


    def initialize(options)
      @monitor = Pushy::Monitor.new(options)
      @ctx = EM::ZeroMQ::Context.new(1)
      @out_address = options[:out_address]
      @in_address = options[:in_address]
      @interval = options[:interval]
      @client_key_path = options[:client_key]
      @server_key_path = options[:server_key]

      @client_private_key = load_key(options[:client_private_key])
      @server_public_key = load_key(options[:server_public_key])
    end

    def start
      Pushy::Log.info "Listening at #{out_address}"

      EM.run do

        # Subscribe to heartbeat from the server
        subscriber = ctx.socket(ZMQ::SUB, Pushy::Handler.new(monitor, server_public_key))
        subscriber.connect(out_address)
        subscriber.setsockopt(ZMQ::SUBSCRIBE, "")

        # Push heartbeat to server
        push_socket = ctx.socket(ZMQ::PUSH)
        push_socket.setsockopt(ZMQ::LINGER, 0)
        push_socket.connect(in_address)

        monitor.start

        seq = 0

        EM::PeriodicTimer.new(interval) do
          if monitor.online?

            json = Yajl::Encoder.encode({:node => (`hostname`).chomp,
                                         :client => (`hostname`).chomp,
                                         :org => "ORG",
                                         :sequence => seq,
                                         :timestamp => Time.now.httpdate})

            auth = "VersionId:0.0.1;SignedChecksum:#{sign_checksum(json)}"

            Pushy::Log.debug "Sending Message #{json}"

            push_socket.send_msg(auth, json)

            seq += 1
          end
        end

      end

    end

    private

    def load_key(key_path)
      raw_key = IO.read(key_path).strip
      OpenSSL::PKey::RSA.new(raw_key)
    end

    def sign_checksum(json)
      checksum = Mixlib::Authentication::Digester.hash_string(json)
      Base64.encode64(client_private_key.private_encrypt(checksum)).chomp
    end

  end
end
