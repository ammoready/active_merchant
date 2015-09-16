require 'test_helper'

class EprocessingNetworkTest < Test::Unit::TestCase
  def setup
    @gateway = EprocessingNetworkGateway.new(ePNAccount: '080880', RestrictKey: 'yFqqXJh9Pqnugfr')
    @credit_card = credit_card
    @transaction_id = '20080828140719-080880-23'
    @failed_transaction_id = '20150914161218-080880-337587-0'
    @amount = 1000
    # An amount ending with '1' returns card declined error (ex. $2.01).
    @failed_amount = 201

    @options = {
      credit_card: @credit_card,
      address: {
        address: '123 Fake St.',
        city: 'Testville',
        state: 'SC',
        zip: '12345',
        phone: '555-555-1234',
      }
    }
  end

  def test_successful_purchase
    @gateway.expects(:ssl_post).returns(successful_purchase_response)

    response = @gateway.purchase(@amount, @options)
    assert_success response

    assert_equal @transaction_id, response.authorization
    assert response.test?
  end

  def test_failed_purchase
    @gateway.expects(:ssl_post).returns(failed_purchase_response)

    response = @gateway.purchase(@failed_amount, @options)
    assert_failure response
    assert_equal Gateway::STANDARD_ERROR_CODE[:card_declined], response.error_code
  end

  def test_successful_authorize
    @gateway.expects(:ssl_post).returns(successful_authorize_response)

    response = @gateway.authorize(@amount, @options)
    assert_success response

    assert_equal @transaction_id, response.authorization
    assert response.test?
  end

  def test_failed_authorize
    @gateway.expects(:ssl_post).returns(failed_authorize_response)

    response = @gateway.authorize(@failed_amount, @options)
    assert_failure response
    assert_equal Gateway::STANDARD_ERROR_CODE[:card_declined], response.error_code
  end

  def test_successful_capture
    @gateway.expects(:ssl_post).returns(successful_capture_response)

    response = @gateway.capture(@amount, { transaction_id: @transaction_id })
    assert_success response

    assert_equal @transaction_id, response.authorization
    assert response.test?
  end

  def test_failed_capture
    @gateway.expects(:ssl_post).returns(failed_capture_response)

    response = @gateway.capture(@failed_amount, { transaction_id: @failed_transaction_id })
    assert_failure response
  end

  def test_successful_refund
    @gateway.expects(:ssl_post).returns(successful_refund_response)

    response = @gateway.refund(@amount, { transaction_id: @transaction_id })
    assert_success response

    assert_equal @transaction_id, response.authorization
    assert response.test?
  end

  def test_failed_refund
    @gateway.expects(:ssl_post).returns(failed_refund_response)

    response = @gateway.refund(@failed_amount, { transaction_id: @failed_transaction_id })
    assert_failure response
  end

  def test_successful_void
  end

  def test_failed_void
  end

  def test_successful_verify
  end

  def test_successful_verify_with_failed_void
  end

  def test_failed_verify
  end

  private

  def successful_purchase_response
    %Q("YAPPROVED 184752","AVS Match 9 Digit Zip and Address (X)","CVV2 Match (M)","23","#{@transaction_id}")
  end

  def failed_purchase_response
    %Q("NDECLINED","Postal Code match - Address not verified - International (P)","CVV2 Match (M)","337587","#{@failed_transaction_id}")
  end

  def successful_authorize_response
    %Q("YAPPROVED 184752","AVS Match 9 Digit Zip and Address (X)","CVV2 Match (M)","23","#{@transaction_id}")
  end

  def failed_authorize_response
    %Q("NDECLINED","Postal Code match - Address not verified - International (P)","CVV2 Match (M)","337587","#{@failed_transaction_id}")
  end

  def successful_capture_response
    %Q("YSUCCESSFUL","","","337607","#{@transaction_id}")
  end

  def failed_capture_response
    %Q("NCannot Find Xact","","","337612","#{@failed_transaction_id}")
  end

  def successful_refund_response
    %Q("YSUCCESSFUL","","","337607","#{@transaction_id}")
  end

  def failed_refund_response
    %Q("UTransID Not Found")
  end

  def successful_void_response
  end

  def failed_void_response
  end
end
