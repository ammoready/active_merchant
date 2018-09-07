module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class EprocessingNetworkGateway < Gateway
      self.test_url = 'https://www.eprocessingnetwork.com/cgi-bin/tdbe/transact.pl'
      self.live_url = 'https://www.eprocessingnetwork.com/cgi-bin/tdbe/transact.pl'

      self.supported_countries = ['US']
      self.default_currency = 'USD'
      self.supported_cardtypes = [:visa, :master, :american_express, :discover]
      self.money_format = :dollars

      self.homepage_url = 'https://www.eprocessingnetwork.com/'
      self.display_name = 'eProcessing Network'

      STANDARD_ERROR_CODE_MAPPING = {}

      # Options for the 'CVV2Type' parameter.
      CVV_TYPES = {
        do_not_use_cvv: 0,
        use_cvv: 1,
        cvv_illegible: 2,
        no_cvv_imprinted: 9,
      }

      def initialize(options = {})
        requires!(options, :ePNAccount, :RestrictKey)
        super
      end

      # TODO: add `payment` argument like other processors
      def purchase(money, options = {})
        post = {}

        add_invoice(post, money, options)
        add_payment(post, options)
        add_address(post, options)
        add_customer_data(post, options)

        commit(:Sale, post)
      end

      def authorize(money, options = {})
        requires!(options, :credit_card, :address)
        post = {}

        add_invoice(post, money, options)
        add_payment(post, options)
        add_address(post, options)
        add_customer_data(post, options)

        commit(:AuthOnly, post)
      end

      def capture(money, options = {})
        requires!(options, :transaction_id)
        post = {}

        add_invoice(post, money, options)
        add_payment(post, options)

        commit(:Auth2Sale, post)
      end

      def refund(money, options = {})
        post = {}

        add_invoice(post, money, options)
        add_payment(post, options)

        commit(:Return, post)
      end

      def void(transaction_id)
        post = {}

        add_payment(post, { transaction_id: transaction_id })

        commit(:Void, post)
      end

      def void_authorization(transaction_id)
        post = {}

        add_payment(post, { transaction_id: transaction_id })

        commit(:AuthDel, post)
      end

      def verify(credit_card, options = {})
        MultiResponse.run(:use_first_response) do |r|
          r.process { authorize(100, { credit_card: credit_card }.merge(options)) }
          r.process(:ignore_result) { void(r.authorization) }
        end
      end

      def store(credit_card, options = {})
        post = {}

        post[:CardNo] = credit_card.number
        post[:ExpMonth] = format(credit_card.month, :two_digits)
        post[:ExpYear] = format(credit_card.year, :two_digits)

        add_address(post, options)
        add_customer_data(post, options)

        commit(:Store, post)
      end

      def supports_scrubbing?
        false
      end

      def scrub(transcript)
        transcript
      end

      private

      def add_customer_data(post, options)
        post[:FirstName] = options[:first_name] unless options[:first_name].nil?
        post[:LastName] = options[:last_name] unless options[:last_name].nil?
        post[:Company] = options[:company] unless options[:company].nil?
      end

      def add_address(post, options)
        return unless options.has_key?(:address)
        address = options[:address]

        post[:Address] = address[:address] unless address[:address].nil?
        post[:City] = address[:city] unless address[:city].nil?
        post[:State] = address[:state] unless address[:state].nil?
        post[:Zip] = address[:zip] unless address[:zip].nil?
        post[:Phone] = address[:phone] unless address[:phone].nil?
      end

      def add_invoice(post, money, options)
        post[:Total] = amount(money)
        post[:Description] = options[:description] unless options[:description].nil?
      end

      def add_payment(post, options)
        if options.has_key?(:transaction_id)
          # Use TransID as payment
          post[:TransID] = options[:transaction_id]
          post[:CVV2Type] = CVV_TYPES[:do_not_use_cvv]
        elsif options.has_key?(:credit_card)
          # Use CreditCard object as payment.
          credit_card = options[:credit_card]

          post[:CardNo] = credit_card.number
          post[:ExpMonth] = format(credit_card.month, :two_digit)
          post[:ExpYear] = format(credit_card.year, :two_digit)
          post[:CVV2Type] = CVV_TYPES[:use_cvv]
          post[:CVV2] = credit_card.verification_value
        else
          raise StandardError, "No payment present in options: #{options.inspect}"
        end
      end

      # Example response:
      # "YAPPROVED 184752","AVS Match 9 Digit Zip and Address (X)","CVV2 Match (M)","23","20080828140719-080880-23"
      def parse(body)
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

      # * <tt>action</tt> - Should be the 'TranType' value for the request body.
      # * <tt>parameters</tt> - Data (hash) to be POSTed as the request body.
      def commit(action, parameters)
        parameters[:HTML] = 'No'

        url = (test? ? test_url : live_url)

        response = parse(ssl_post(url, post_data(action, parameters)))

        Response.new(
          success_from(response),
          message_from(response),
          response,
          authorization: authorization_from(response),
          avs_result: avs_result_from(response),
          cvv_result: cvv_result_from(response),
          test: test?,
          error_code: error_code_from(response)
        )
      end

      def success_from(response)
        response[:response].start_with?('Y')
      end

      def message_from(response)
        # Strip the first char ('Y', 'N', or 'U') to get just the response message.
        response[:response].gsub(/\A./, '')
      end

      def avs_result_from(response)
        code_match = response[:avs_response].match(/\((.)\)\Z/)
        code_match ? AVSResult.new(code: code_match[0].gsub(/\(|\)/, '')) : nil
      end

      def cvv_result_from(response)
        code_match = response[:cvv_response].match(/\((.)\)\Z/)
        code_match ? CVVResult.new(code_match[0].gsub(/\(|\)/, '')) : nil
      end

      def authorization_from(response)
        response[:transaction_id]
      end

      def post_data(action, parameters = {})
        parameters[:TranType] = case action
        when :Auth2Sale
          'Auth2Sale'
        when :AuthOnly
          'AuthOnly'
        when :AuthDel
          'AuthDel'
        when :Return
          'Return'
        when :Sale
          'Sale'
        when :Store
          'Store'
        when :Void
          'Void'
        else
          raise StandardError, "Unknown TranType: #{action}"
        end

        # Add authentication params.
        parameters[:ePNAccount] = @options[:ePNAccount]
        parameters[:RestrictKey] = @options[:RestrictKey]

        # Turn the POST params hash into a key/value string.
        parameters.map { |key, value| "#{key}=#{value}" }.join('&')
      end

      def error_code_from(response)
        return if success_from(response)

        if response[:response] == 'NDECLINED'
          STANDARD_ERROR_CODE[:card_declined]
        end
      end
    end
  end
end
