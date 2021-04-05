module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class ZeamsterGateway < Gateway
      self.test_url = 'https://api.sandbox.zeamster.com/v2'
      self.live_url = 'https://api.zeamster.com/v2'

      self.supported_countries = ['US']
      self.default_currency = 'USD'
      self.supported_cardtypes = [:visa, :master, :american_express, :discover]
      self.money_format = :dollars

      self.homepage_url = 'https://www.zeamster.com/'
      self.display_name = 'Zeamster'

      TRANSACTION_URLS = {
        [:sale, :authonly, :refund] => "%s/transactions".freeze,
        [:authcomplete, :void]      => "%s/transactions/%s".freeze
      }

      # https://docs.zeamster.com/developers/api/response-reason-codes
      STANDARD_ERROR_CODE_MAPPING = {
        '1500' => STANDARD_ERROR_CODE[:card_declined],
        '1510' => STANDARD_ERROR_CODE[:call_issuer],
        '1518' => STANDARD_ERROR_CODE[:unsupported_feature],
        '1520' => STANDARD_ERROR_CODE[:pickup_card],
        '1530' => STANDARD_ERROR_CODE[:processing_error],
        '1530' => STANDARD_ERROR_CODE[:processing_error],
        '1540' => STANDARD_ERROR_CODE[:config_error],
        '1541' => STANDARD_ERROR_CODE[:processing_error],
        '1588' => STANDARD_ERROR_CODE[:processing_error],
        '1599' => STANDARD_ERROR_CODE[:processing_error],
        '1601' => STANDARD_ERROR_CODE[:card_declined],
        '1602' => STANDARD_ERROR_CODE[:call_issuer],
        '1603' => STANDARD_ERROR_CODE[:processing_error],
        '1604' => STANDARD_ERROR_CODE[:pickup_card],
        '1605' => STANDARD_ERROR_CODE[:pickup_card],
        '1606' => STANDARD_ERROR_CODE[:pickup_card],
        '1607' => STANDARD_ERROR_CODE[:pickup_card],
        '1608' => STANDARD_ERROR_CODE[:processing_error],
        '1609' => STANDARD_ERROR_CODE[:processing_error],
        '1610' => STANDARD_ERROR_CODE[:incorrect_pin],
        '1611' => STANDARD_ERROR_CODE[:processing_error],
        '1612' => STANDARD_ERROR_CODE[:processing_error],
        '1613' => STANDARD_ERROR_CODE[:invalid_cvc],
        '1614' => STANDARD_ERROR_CODE[:invalid_expiry_date],
        '1615' => STANDARD_ERROR_CODE[:card_declined],
        '1616' => STANDARD_ERROR_CODE[:card_declined],
        '1617' => STANDARD_ERROR_CODE[:card_declined],
        '1618' => STANDARD_ERROR_CODE[:processing_error],
        '1619' => STANDARD_ERROR_CODE[:card_declined],
        '1620' => STANDARD_ERROR_CODE[:card_declined],
        '1621' => STANDARD_ERROR_CODE[:processing_error],
        '1622' => STANDARD_ERROR_CODE[:expired_card],
        '1623' => STANDARD_ERROR_CODE[:card_declined],
        '1624' => STANDARD_ERROR_CODE[:card_declined],
        '1625' => STANDARD_ERROR_CODE[:card_declined],
        '1626' => STANDARD_ERROR_CODE[:processing_error],
        '1627' => STANDARD_ERROR_CODE[:processing_error],
        '1628' => STANDARD_ERROR_CODE[:config_error],
        '1629' => STANDARD_ERROR_CODE[:processing_error],
        '1630' => STANDARD_ERROR_CODE[:processing_error],
        '1631' => STANDARD_ERROR_CODE[:processing_error],
        '1641' => STANDARD_ERROR_CODE[:processing_error],
        '1650' => STANDARD_ERROR_CODE[:processing_error],
        '1652' => STANDARD_ERROR_CODE[:processing_error],
        '1653' => STANDARD_ERROR_CODE[:processing_error],
        '1654' => STANDARD_ERROR_CODE[:processing_error],
        '1655' => STANDARD_ERROR_CODE[:incorrect_address],
        '1656' => STANDARD_ERROR_CODE[:incorrect_cvc],
        '1657' => STANDARD_ERROR_CODE[:card_declined],
        '1658' => STANDARD_ERROR_CODE[:processing_error],
        '1659' => STANDARD_ERROR_CODE[:card_declined],
        '1660' => STANDARD_ERROR_CODE[:processing_error],
        '1661' => STANDARD_ERROR_CODE[:card_declined],
        '1662' => STANDARD_ERROR_CODE[:processing_error],
        '1663' => STANDARD_ERROR_CODE[:processing_error],
        '1664' => STANDARD_ERROR_CODE[:processing_error],
        '1665' => STANDARD_ERROR_CODE[:processing_error],
        '1701' => STANDARD_ERROR_CODE[:card_declined],
        '1800' => STANDARD_ERROR_CODE[:incorrect_cvc],
        '1801' => STANDARD_ERROR_CODE[:processing_error],
        '1802' => STANDARD_ERROR_CODE[:config_error],
        '1803' => STANDARD_ERROR_CODE[:processing_error],
        '1804' => STANDARD_ERROR_CODE[:processing_error],
        '1805' => STANDARD_ERROR_CODE[:processing_error]
      }

      def initialize(options={})
        requires!(options, :user_id, :api_key, :developer_id)
        super
      end

      def purchase(money, credit_card, options = {})
        post = { transaction: {} }

        add_invoice(post, money, options)
        add_payment(post, credit_card)
        add_customer_data(post, credit_card, options)
        add_address(post, options)

        commit(:sale, :post, post)
      end

      def authorize(money, credit_card, options = {})
        post = { transaction: {} }

        add_invoice(post, money, options)
        add_payment(post, credit_card)
        add_customer_data(post, credit_card, options)
        add_address(post, options)

        commit(:authonly, :post, post)
      end

      def capture(money, transaction_id, options = {})
        post = { transaction: { transaction_amount: amount(money) } }

        commit(:authcomplete, :post, post, transaction_id)
      end

      def void(transaction_id)
        commit(:void, :put, { transaction: {} }, transaction_id)
      end

      def refund(money, transaction_id)
        post = {
          transaction: {
            previous_transaction_id: transaction_id,
            payment_method: 'cc',
            transaction_amount: amount(money)
          }
        }

        commit(:refund, :post, post)
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

      def add_customer_data(post, credit_card, options)
        post[:transaction][:account_holder_name] = [credit_card.first_name, credit_card.last_name].join(' ')
      end

      def add_address(post, options)
        billing_address = options[:billing_address] || options[:address] || {}

        post[:transaction][:billing_street] = billing_address[:address1] unless billing_address[:address1].nil?
        post[:transaction][:billing_city]   = billing_address[:city] unless billing_address[:city].nil?
        post[:transaction][:billing_state]  = billing_address[:state] unless billing_address[:state].nil?
        post[:transaction][:billing_zip]    = billing_address[:zip] unless billing_address[:zip].nil?
        post[:transaction][:billing_phone]  = billing_address[:phone] unless billing_address[:phone].nil?
      end

      def add_invoice(post, money, options)
        post[:transaction][:transaction_amount] = amount(money)
        post[:transaction][:tax]                = options[:tax] unless options[:tax].nil?
        post[:transaction][:description]        = options[:description].truncate(64) unless options[:description].nil?
        post[:transaction][:order_num]          = options[:order_id] unless options[:order_id].nil?
        post[:transaction][:po_number]          = options[:po_number] unless options[:po_number].nil?
        post[:transaction][:customer_ip]        = options[:ip_address] unless options[:ip_address].nil?
        post[:transaction][:notification_email_address] = options[:email] if (options[:email_receipt] || false)
      end

      def add_payment(post, credit_card)
        post[:transaction][:payment_method] = 'cc'
        post[:transaction][:account_number] = credit_card.number
        post[:transaction][:exp_date]       = expdate(credit_card)
        post[:transaction][:cvv]            = credit_card.verification_value
      end

      def parse(body)
        JSON.parse(body).deep_symbolize_keys
      end

      def commit(action, method, parameters, transaction_id = nil)
        response = raw_ssl_request(method, transaction_url(action, transaction_id), post_data(action, parameters), headers)
        response_body = parse(response.body)

        Response.new(
          success_from(response, response_body),
          message_from(response),
          response_body,
          authorization: authorization_from(response_body),
          avs_result:    avs_result_from(response_body),
          cvv_result:    cvv_result_from(response_body),
          test:          test?,
          error_code:    error_code_from(response_body)
        )
      end

      def transaction_url(action, transaction_id)
        root_url = (test? ? test_url : live_url)

        TRANSACTION_URLS.find { |k, v| action.in?(k) }[1] % [root_url, transaction_id]
      end

      def expdate(credit_card)
        "#{format(credit_card.month, :two_digits)}#{format(credit_card.year, :two_digits)}"
      end

      def success_from(response, body)
        response.code.to_i.in?(200..204) && body[:transaction].try(:[], :reason_code_id).in?(1000..1240)
      end

      def message_from(response)
        response.message
      end

      def authorization_from(body)
        body[:transaction].try(:[], :id)
      end

      def avs_result_from(body)
        AVSResult.new(code: body[:transaction].try(:[], :avs_enhanced))
      end

      def cvv_result_from(body)
        CVVResult.new(body[:transaction].try(:[], :cvv_response))
      end

      def error_code_from(body)
        STANDARD_ERROR_CODE_MAPPING[body[:transaction].try(:[], :reason_code_id)]
      end

      def post_data(action, parameters)
        parameters[:transaction][:action] = action

        parameters.to_json
      end

      def headers
        {
          'Content-Type': 'application/json',
          'Developer-ID': @options[:developer_id],
          'User-ID':      @options[:user_id],
          'User-API-Key': @options[:api_key]
        }
      end
    end
  end
end
