module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class BlueDogCustomerVaultGateway < Gateway
      self.test_url = 'https://bluedog.transactiongateway.com/api/transact.php'
      self.live_url = 'https://bluedog.transactiongateway.com/api/transact.php'

      self.supported_countries = ['US']
      self.default_currency = 'USD'
      self.supported_cardtypes = [:visa, :master, :american_express, :discover]

      self.homepage_url = 'http://blue-dog.com/'
      self.display_name = 'Blue Dog'

      STANDARD_ERROR_CODE_MAPPING = {}

      def initialize(options={})
        requires!(options, :login, :password)
        super
      end

      def add_customer(payment, options={})
        post = { customer_vault: 'add_customer' }

        add_payment(post, payment)
        add_address(post, options)
        add_customer_data(post, payment, options)

        commit(post)
      end

      def update_customer(customer_vault_id, payment, options={})
        post = {
          customer_vault: 'update_customer',
          customer_vault_id: customer_vault_id
        }

        add_payment(post, payment)
        add_address(post, options)
        add_customer_data(post, payment, options)

        commit(post)
      end

      def delete_customer(customer_vault_id)
        post = {
          customer_vault: 'delete_customer',
          customer_vault_id: customer_vault_id
        }

        commit(post)
      end

      def purchase(money, customer_vault_id, options={})
        post = { type: 'sale', customer_vault_id: customer_vault_id }

        add_invoice(post, money, options)
        commit(post)
      end

      def authorize(money, customer_vault_id, options={})
        post = { type: 'auth', customer_vault_id: customer_vault_id }

        add_invoice(post, money, options)
        commit(post)
      end

      def capture(money, authorization, customer_vault_id, options={})
        post = {
          type: 'capture',
          amount: amount(money),
          transactionid: authorization,
          customer_vault_id: customer_vault_id
        }
        commit(post)
      end

      def refund(money, authorization, customer_vault_id, options={})
        post = {
          type: 'refund',
          amount: amount(money),
          transactionid: authorization,
          customer_vault_id: customer_vault_id
        }
        commit(post)
      end

      def void(authorization, customer_vault_id, options={})
        post = {
          type: 'void',
          transactionid: authorization,
          customer_vault_id: customer_vault_id
        }
        commit(post)
      end

      def supports_scrubbing?
        false
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

        billing_email = options[:email] ? options[:email] : (billing_address[:email] ? billing_address[:email] : nil)
        shipping_email = shipping_address[:email] ? shipping_address[:email] : billing_email

        post[:address1] = billing_address[:address1] unless billing_address[:address1].nil?
        post[:address2] = billing_address[:address2] unless billing_address[:address2].nil?
        post[:city] = billing_address[:city] unless billing_address[:city].nil?
        post[:state] = billing_address[:state] unless billing_address[:state].nil?
        post[:zip] = billing_address[:zip] unless billing_address[:zip].nil?
        post[:phone] = billing_address[:phone] unless billing_address[:phone].nil?
        post[:fax] = billing_address[:fax] unless billing_address[:fax].nil?
        post[:email] = billing_email unless billing_email.nil?

        post[:shipping_address1] = shipping_address[:address1] unless shipping_address[:address1].nil?
        post[:shipping_address2] = shipping_address[:address2] unless shipping_address[:address2].nil?
        post[:shipping_city] = shipping_address[:city] unless shipping_address[:city].nil?
        post[:shipping_state] = shipping_address[:state] unless shipping_address[:state].nil?
        post[:shipping_zip] = shipping_address[:zip] unless shipping_address[:zip].nil?
        post[:shipping_email] = shipping_email unless shipping_email.nil?
      end

      def add_invoice(post, money, options)
        post[:amount] = amount(money)
        post[:currency] = (options[:currency] || currency(money))
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
      # "response=1&responsetext=Customer Added&authcode=&transactionid=&avsresponse=&cvvresponse=&orderid=&type=&response_code=100&customer_vault_id=842085207"
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
        response[:customer_vault_id] = parsed_body[:customer_vault_id]

        response
      end

      def commit(parameters)
        url = (test? ? test_url : live_url)
        response = parse(ssl_post(url, post_data(parameters)))

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
        response[:response] == ActiveMerchant::Billing::BlueDogGateway::RESPONSES[:approved]
      end

      def message_from(response)
        ActiveMerchant::Billing::BlueDogGateway::RESPONSE_MESSAGES[response[:response_code]]
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

      def post_data(parameters = {})
        parameters[:username] = @options[:login]
        parameters[:password] = @options[:password]

        # Turn the POST params hash into a key/value string.
        parameters.map { |key, value| "#{key}=#{URI.escape(value)}" }.join('&')
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
    end
  end
end
