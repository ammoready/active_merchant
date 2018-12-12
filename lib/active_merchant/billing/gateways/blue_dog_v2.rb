module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class BlueDogV2Gateway < Gateway
      self.test_url = 'https://sandbox.bluedogpayments.com/api'
      self.live_url = 'https://app.bluedogpayments.com/api'

      self.supported_countries = ['US']
      self.default_currency = 'USD'
      self.supported_cardtypes = [:visa, :master, :american_express, :discover]
      self.money_format = :cents

      self.homepage_url = 'http://blue-dog.com/'
      self.display_name = 'Blue Dog 2.0'

      TRANSACTION_URLS = {
        sale:      "%s/transaction".freeze,
        authorize: "%s/transaction".freeze,
        capture:   "%s/transaction/%s/capture".freeze,
        void:      "%s/transaction/%s/void".freeze,
        refund:    "%s/transaction/%s/refund".freeze,
      }

      TYPE_REQUIRED_ACTIONS = %i( sale authorize ).freeze

      def initialize(options={})
        requires!(options, :api_key)
        super
      end

      def purchase(money, payment, options = {})
        post = {}
        add_invoice(post, money, options)
        add_payment(post, payment)
        add_customer_data(post, payment, options)
        add_address(post, options)

        commit(:sale, post)
      end

      def authorize(money, payment, options = {})
        post = {}
        add_invoice(post, money, options)
        add_payment(post, payment)
        add_customer_data(post, payment, options)
        add_address(post, options)

        commit(:authorize, post)
      end

      def capture(money, transaction_id, options = {})
        post                   = {}
        post[:amount]          = amount(money)
        post[:tax_amount]      = options[:tax_amount] unless options[:tax_amount].nil?
        post[:tax_exempt]      = options[:tax_exempt] || false
        post[:shipping_amount] = options[:shipping_amount] unless options[:shipping_amount].nil?

        commit(:capture, post, transaction_id)
      end

      def void(transaction_id)
        commit(:void, {}, transaction_id)
      end

      def refund(money, transaction_id)
        post = { amount: amount(money) }

        commit(:refund, post, transaction_id)
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
        post[:billing_address] = {}

        post[:billing_address][:first_name] = creditcard.first_name
        post[:billing_address][:last_name]  = creditcard.last_name
        post[:billing_address][:email]      = options[:email]
      end

      def add_address(post, options)
        billing_address  = options[:billing_address]  || options[:address] || {}
        shipping_address = options[:shipping_address] || options[:address] || {}
        post[:shipping_address] = {}

        post[:billing_address][:first_name]     ||= billing_address[:first_name]
        post[:billing_address][:last_name]      ||= billing_address[:last_name]
        post[:billing_address][:company]        = billing_address[:company] unless billing_address[:company].nil?
        post[:billing_address][:address_line_1] = billing_address[:address1] unless billing_address[:address1].nil?
        post[:billing_address][:city]           = billing_address[:city] unless billing_address[:city].nil?
        post[:billing_address][:state]          = billing_address[:state] unless billing_address[:state].nil?
        post[:billing_address][:postal_code]    = billing_address[:zip] unless billing_address[:zip].nil?
        post[:billing_address][:country]        = billing_address[:country] unless billing_address[:country].nil?
        post[:billing_address][:phone]          = billing_address[:phone] unless billing_address[:phone].nil?
        post[:billing_address][:fax]            = billing_address[:fax] unless billing_address[:fax].nil?
        post[:billing_address][:email]          ||= billing_address[:email]

        shipping_email = shipping_address[:email] || post[:billing_address][:email]

        post[:shipping_address][:first_name]     = shipping_address[:first_name] unless shipping_address[:first_name].nil?
        post[:shipping_address][:last_name]      = shipping_address[:last_name] unless shipping_address[:last_name].nil?
        post[:shipping_address][:company]        = shipping_address[:company] unless shipping_address[:company].nil?
        post[:shipping_address][:address_line_1] = shipping_address[:address1] unless shipping_address[:address1].nil?
        post[:shipping_address][:city]           = shipping_address[:city] unless shipping_address[:city].nil?
        post[:shipping_address][:state]          = shipping_address[:state] unless shipping_address[:state].nil?
        post[:shipping_address][:postal_code]    = shipping_address[:zip] unless shipping_address[:zip].nil?
        post[:shipping_address][:country]        = shipping_address[:country] unless shipping_address[:country].nil?
        post[:shipping_address][:phone]          = shipping_address[:phone] unless shipping_address[:phone].nil?
        post[:shipping_address][:fax]            = shipping_address[:fax] unless shipping_address[:fax].nil?
        post[:shipping_address][:email]          = shipping_email unless shipping_email.nil?
      end

      def add_invoice(post, money, options)
        post[:amount]          = amount(money)
        post[:tax_amount]      = amount(options[:tax]) unless options[:tax].nil?
        post[:shipping_amount] = amount(options[:shipping]) unless options[:shipping].nil?
        post[:currency]        = options[:currency] || 'USD'
        post[:description]     = options[:description] unless options[:description].nil?
        post[:order_id]        = options[:order_id] unless options[:order_id].nil?
        post[:po_number]       = options[:po_number] unless options[:po_number].nil?
        post[:ip_address]      = options[:ip_address] unless options[:ip_address].nil?
        post[:email_receipt]   = options[:email_receipt] || false
        post[:email_address]   = options[:email] if post[:email_receipt]
      end

      def add_payment(post, payment)
        post[:payment_method] = {
          card: {
            entry_type:      'keyed',
            number:          payment.number,
            expiration_date: expdate(payment),
            cvc:             payment.verification_value,
          }
        }
      end

      def parse(body)
        JSON.parse(body).deep_symbolize_keys
      end

      def commit(action, parameters, transaction_id = nil)
        response = parse(ssl_post(transaction_url(action, transaction_id), post_data(action, parameters), headers))

        Response.new(
          success_from(response),
          message_from(response),
          response,
          authorization: authorization_from(response),
          avs_result:    avs_result_from(response),
          cvv_result:    cvv_result_from(response),
          test:          test?,
          error_code:    error_code_from(response)
        )
      end

      def transaction_url(action, transaction_id)
        root_url = (test? ? test_url : live_url)

        TRANSACTION_URLS[action] % [root_url, transaction_id]
      end

      def expdate(credit_card)
        "#{format(credit_card.month, :two_digits)}/#{format(credit_card.year, :two_digits)}"
      end

      def success_from(response)
        response[:status] == 'success'
      end

      def message_from(response)
        response[:data][:response]
      end

      def authorization_from(response)
        response[:data][:id]
      end

      def avs_result_from(response)
        AVSResult.new(code: response[:data][:response_body][:card][:avs_response_code])
      end

      def cvv_result_from(response)
        CVVResult.new(response[:data][:response_body][:card][:cvv_response_code])
      end

      def error_code_from(response)
        response[:data][:response_code] unless success_from(response)
      end

      def post_data(action, parameters)
        parameters[:type] = action if TYPE_REQUIRED_ACTIONS.include?(action)

        parameters.to_json
      end

      def headers
        {
          'Content-Type'  => 'application/json',
          'Authorization' => @options[:api_key],
        }
      end
    end
  end
end
