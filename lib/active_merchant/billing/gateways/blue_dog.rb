module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class BlueDogGateway < Gateway
      self.test_url = 'https://bluedog.transactiongateway.com/api/transact.php'
      self.live_url = 'https://bluedog.transactiongateway.com/api/transact.php'

      self.supported_countries = ['US']
      self.default_currency = 'USD'
      self.supported_cardtypes = [:visa, :master, :american_express, :discover]

      self.homepage_url = 'http://blue-dog.com/'
      self.display_name = 'Blue Dog'

      STANDARD_ERROR_CODE_MAPPING = {}

      RESPONSES = {
        approved: '1',
        declined: '2',
        error:    '3',
      }

      RESPONSE_MESSAGES = {
        100 => 'Transaction was approved.',
        200 => 'Transaction was declined by processor.',
        201 => 'Do not honor.',
        202 => 'Insufficient funds.',
        203 => 'Over limit.',
        204 => 'Transaction not allowed.',
        220 => 'Incorrect payment information.',
        221 => 'No such card issuer.',
        222 => 'No card number on file with issuer.',
        223 => 'Expired card.',
        224 => 'Invalid expiration date.',
        225 => 'Invalid card security code.',
        240 => 'Call issuer for further information.',
        250 => 'Pick up card.',
        251 => 'Lost card.',
        252 => 'Stolen card.',
        253 => 'Fraudulent card.',
        260 => 'Declined with further instructions available. (See response text)',
        261 => 'Declined-Stop all recurring payments.',
        262 => 'Declined-Stop this recurring program.',
        263 => 'Declined-Update cardholder data available.',
        264 => 'Declined-Retry in a few days.',
        300 => 'Transaction was rejected by gateway.',
        400 => 'Transaction error returned by processor.',
        410 => 'Invalid merchant configuration.',
        411 => 'Merchant account is inactive.',
        420 => 'Communication error.',
        421 => 'Communication error with issuer.',
        430 => 'Duplicate transaction at processor.',
        440 => 'Processor format error.',
        441 => 'Invalid transaction information.',
        460 => 'Processor feature not available.',
        461 => 'Unsupported card type.',
      }

      def initialize(options={})
        requires!(options, :login, :password)
        super
      end

      def purchase(money, payment, options={})
        post = {}
        add_invoice(post, money, options)
        add_payment(post, payment)
        add_address(post, options)
        add_customer_data(post, payment, options)

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
        post = {}
        post[:amount] = amount(money)
        post[:transactionid] = authorization

        commit('capture', post)
      end

      def refund(money, authorization, options={})
        post = {}
        post[:amount] = amount(money)
        post[:transactionid] = authorization

        commit('refund', post)
      end

      def void(authorization, options={})
        post = {}
        post[:transactionid] = authorization

        commit('void', post)
      end

      def verify(credit_card, options={})
        MultiResponse.run(:use_first_response) do |r|
          r.process { authorize(100, credit_card, options) }
          r.process(:ignore_result) { void(r.authorization, options) }
        end
      end

      def supports_scrubbing?
        true
      end

      def scrub(transcript)
        transcript
      end

      private

      def add_customer_data(post, creditcard, options)
        post[:first_name] = creditcard.first_name
        post[:last_name] = creditcard.last_name
        post[:company] = options[:company] unless options[:company].nil?
      end

      def add_address(post, options)
        billing_address  = options[:billing_address]  || options[:address] || {}
        shipping_address = options[:shipping_address] || options[:address] || {}

        post[:address1] = billing_address[:address1] unless billing_address[:address1].nil?
        post[:address2] = billing_address[:address2] unless billing_address[:address2].nil?
        post[:city] = billing_address[:city] unless billing_address[:city].nil?
        post[:state] = billing_address[:state] unless billing_address[:state].nil?
        post[:zip] = billing_address[:zip] unless billing_address[:zip].nil?
        post[:phone] = billing_address[:phone] unless billing_address[:phone].nil?
        post[:fax] = billing_address[:fax] unless billing_address[:fax].nil?
        post[:email] = billing_address[:email] unless billing_address[:email].nil?

        post[:shipping_address1] = shipping_address[:shipping_address1] unless shipping_address[:shipping_address1].nil?
        post[:shipping_address2] = shipping_address[:shipping_address2] unless shipping_address[:shipping_address2].nil?
        post[:shipping_city] = shipping_address[:shipping_city] unless shipping_address[:shipping_city].nil?
        post[:shipping_state] = shipping_address[:shipping_state] unless shipping_address[:shipping_state].nil?
        post[:shipping_zip] = shipping_address[:shipping_zip] unless shipping_address[:shipping_zip].nil?
        post[:shipping_email] = shipping_address[:shipping_email] unless shipping_address[:shipping_email].nil?
      end

      def add_invoice(post, money, options)
        post[:amount] = amount(money)
        post[:tax] = ("%.2f" % options[:tax]) unless options[:tax].nil?
        post[:shipping] = ("%.2f" % options[:shipping]) unless options[:shipping].nil?

        post[:orderid] = options[:order_id] unless options[:order_id].nil?
        post[:orderdescription] = options[:order_description] unless options[:order_description].nil?
        post[:ponumber] = options[:po_number] unless options[:po_number].nil?
      end

      def add_payment(post, payment)
        post[:ccnumber] = payment.number
        post[:ccexp] = expdate(payment)
        post[:cvv] = payment.verification_value
      end

      # Example response:
      # "response=1&responsetext=SUCCESS&authcode=123456&transactionid=3325976945&avsresponse=N&cvvresponse=N&orderid=&type=sale&response_code=100"
      def parse(body)
        response = {}

        # Turn the body string into key-value pairs.
        parsed_body = {}
        body.split('&').each do |piece|
          parsed_body[piece.split('=')[0].to_sym] = piece.split('=')[1]
        end

        response[:response] = parsed_body[:response]
        response[:response_text] = parsed_body[:responsetext]
        response[:response_code] = parsed_body[:response_code].to_i
        response[:avs_response] = parsed_body[:avsresponse]
        response[:cvv_response] = parsed_body[:cvvresponse]
        response[:authorization] = parsed_body[:transactionid]
        response[:auth_code] = parsed_body[:authcode]

        response
      end

      def commit(action, parameters)
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
        response[:response] == RESPONSES[:approved]
      end

      def message_from(response)
        RESPONSE_MESSAGES[response[:response_code]]
      end

      def authorization_from(response)
        response[:authorization]
      end

      def avs_result_from(response)
        AVSResult.new(code: response[:avs_response])
      end

      def cvv_result_from(response)
        CVVResult.new(response[:cvv_response])
      end

      def error_code_from(response)
        return if success_from(response)

        # Response codes here: https://bluedog.transactiongateway.com/merchants/resources/integration/integration_portal.php?tid=ddc79d1e6e1fe963b25737e2b265661d#dp_appendix_3
        case response[:response_code]
        when 200
          STANDARD_ERROR_CODE[:card_declined]
        when 220
          STANDARD_ERROR_CODE[:invalid_number]
        when 222
          STANDARD_ERROR_CODE[:incorrect_number]
        when 223
          STANDARD_ERROR_CODE[:expired_card]
        when 224
          STANDARD_ERROR_CODE[:invalid_expiry_date]
        when 225
          STANDARD_ERROR_CODE[:invalid_cvc]
        when 240
          STANDARD_ERROR_CODE[:call_issuer]
        when 250
          STANDARD_ERROR_CODE[:pickup_card]
        when 410
          STANDARD_ERROR_CODE[:config_error]
        when 440
          STANDARD_ERROR_CODE[:processing_error]
        end
      end

      def post_data(action, parameters = {})
        parameters[:type] = action

        parameters[:username] = @options[:login]
        parameters[:password] = @options[:password]

        # Turn the POST params hash into a key/value string.
        parameters.map { |key, value| "#{key}=#{URI.escape(value)}" }.join('&')
      end
    end
  end
end
