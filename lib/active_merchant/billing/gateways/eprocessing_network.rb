module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class EprocessingNetworkGateway < Gateway
      self.test_url = 'https://www.eprocessingnetwork.com/cgi-bin/tdbe/transact.pl'
      self.live_url = 'https://www.eprocessingnetwork.com/cgi-bin/tdbe/transact.pl'

      self.supported_countries = ['US']
      self.default_currency = 'USD'
      self.supported_cardtypes = [:visa, :master, :american_express, :discover]
      self.money_format = :cents

      self.homepage_url = 'https://www.eprocessingnetwork.com/'
      self.display_name = 'eProcessing Network'

      STANDARD_ERROR_CODE_MAPPING = {}

      def initialize(options={})
        requires!(options, :ePNAccount, :RestrictKey)
        @gateway_options = options
        super
      end

      def purchase(money, payment, options={})
        post = {}
        add_invoice(post, money, options)
        add_payment(post, payment)
        add_address(post, payment, options)
        add_customer_data(post, options)

        commit('sale', post)
      end

      def authorize(money, payment, options={})
        post = {}
        add_invoice(post, money, options)
        add_payment(post, payment)
        add_address(post, payment, options)
        add_customer_data(post, options)

        commit('authonly', post)
      end

      def capture(money, authorization, options={})
        commit('capture', post)
      end

      def refund(money, authorization, options={})
        commit('refund', post)
      end

      def void(authorization, options={})
        commit('void', post)
      end

      def verify(credit_card, options={})
        MultiResponse.run(:use_first_response) do |r|
          r.process { authorize(100, credit_card, options) }
          r.process(:ignore_result) { void(r.authorization, options) }
        end
      end

      def store(credit_card, options={})
        parameters = {
          CardNo: credit_card.number,
          ExpMonth: format(credit_card.month, :two_digits),
          ExpYear: format(credit_card.year, :two_digits),
        }.merge(options)

        commit(:Store, parameters)
      end

      def supports_scrubbing?
        true
      end

      def scrub(transcript)
        transcript
      end

      private

      def add_customer_data(post, options)
      end

      def add_address(post, creditcard, options)
      end

      def add_invoice(post, money, options)
        post[:amount] = amount(money)
        post[:currency] = (options[:currency] || currency(money))
      end

      def add_payment(post, payment)
      end

      # Example response:
      # "YAPPROVED 184752","AVS Match 9 Digit Zip and Address (X)","CVV2 Match (M)","23","20080828140719-080880-23"
      def parse(body)
        STDOUT.puts "-- DEBUG: #{self.class}#parse() body: #{body.inspect}"
        response = {}

        # Remove the double quotes from response values.
        values = body.split(',').map { |value| value.gsub(/\A"|"\Z/, '') }

        # Transaction Response: String that beings with 'Y', 'N', or 'U'
        response[:response] = values[0].to_s

        response[:avs_response] = values[1].to_s
        response[:cvv_response] = values[2].to_s
        response[:invoice_number] = values[3].to_s
        response[:transaction_id] = values[4].to_s

        response
      end

      def commit(action, parameters)
        parameters[:HTML] = 'No'

        url = (test? ? test_url : live_url)

        STDOUT.puts "-- DEBUG: #{self.class}#commit() parameters: #{parameters.inspect}"
        STDOUT.puts "-- DEBUG: #{self.class}#commit() url: #{url.inspect}"
        STDOUT.puts "-- DEBUG: #{self.class}#commit() post_data(): #{post_data(action, parameters).inspect}"

        response = parse(ssl_post(url, post_data(action, parameters)))

        STDOUT.puts "-- DEBUG: #{self.class}#commit() response: #{response.inspect}"

        Response.new(
          success_from(response),
          message_from(response),
          response,
          authorization: authorization_from(response),
          avs_result: AVSResult.new(code: response["some_avs_response_key"]),
          cvv_result: CVVResult.new(response["some_cvv_response_key"]),
          test: test?,
          error_code: error_code_from(response)
        )
      end

      def success_from(response)
      end

      def message_from(response)
      end

      def authorization_from(response)
      end

      def post_data(action, parameters = {})
        parameters[:TranType] = case action
        when :Store
          'Store'
        else
          raise StandardError, "Unknown TranType: #{action}"
        end

        parameters[:ePNAccount] = @options[:ePNAccount]
        parameters[:RestrictKey] = @options[:RestrictKey]

        # Turn the POST params hash into a key/value string.
        parameters.map { |key, value| "#{key}=#{value}" }.join('&')
      end

      def error_code_from(response)
        unless success_from(response)
          # TODO: lookup error code for this response
        end
      end
    end
  end
end
