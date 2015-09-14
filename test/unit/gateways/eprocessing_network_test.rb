require 'test_helper'

class EprocessingNetworkTest < Test::Unit::TestCase
  def setup
    @gateway = EprocessingNetworkGateway.new(ePNAccount: '080880', RestrictKey: 'yFqqXJh9Pqnugfr')
    @credit_card = credit_card
    @amount = 1000
  end

  def test_successful_purchase
    @gateway.expects(:ssl_post).returns(successful_purchase_response)

    options = {
      credit_card: @credit_card
    }

    response = @gateway.purchase(@amount, options)
    assert_success response

    assert_equal '20080828140719-080880-23', response.authorization
    assert response.test?
  end

  def test_failed_purchase
    @gateway.expects(:ssl_post).returns(failed_purchase_response)

    options = {
      credit_card: @credit_card
    }

    # An amount ending with '1' returns card declined error (ex. $2.01).
    response = @gateway.purchase(20, options)
    assert_failure response
    assert_equal Gateway::STANDARD_ERROR_CODE[:card_declined], response.error_code
  end

  def test_successful_authorize
  end

  def test_failed_authorize
  end

  def test_successful_capture
  end

  def test_failed_capture
  end

  def test_successful_refund
  end

  def test_failed_refund
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
    %q("YAPPROVED 184752","AVS Match 9 Digit Zip and Address (X)","CVV2 Match (M)","23","20080828140719-080880-23")
  end

  def failed_purchase_response
    %q("NDECLINED","Postal Code match - Address not verified - International (P)","CVV2 Match (M)","337587","20150914161218-080880-337587-0")
  end

  def successful_authorize_response
  end

  def failed_authorize_response
  end

  def successful_capture_response
  end

  def failed_capture_response
  end

  def successful_refund_response
  end

  def failed_refund_response
  end

  def successful_void_response
  end

  def failed_void_response
  end
end
