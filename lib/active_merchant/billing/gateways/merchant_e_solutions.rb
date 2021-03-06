module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class MerchantESolutionsGateway < Gateway

      TEST_URL = 'https://cert.merchante-solutions.com/mes-api/tridentApi'
      LIVE_URL = 'https://api.merchante-solutions.com/mes-api/tridentApi'

      # The countries the gateway supports merchants from as 2 digit ISO country codes
      self.supported_countries = ['US']

      # The card types supported by the payment gateway
      self.supported_cardtypes = [:visa, :master, :american_express, :discover, :jcb]

      # The homepage URL of the gateway
      self.homepage_url = 'http://www.merchante-solutions.com/'

      # The name of the gateway
      self.display_name = 'Merchant e-Solutions'

      def initialize(options = {})
        requires!(options, :login, :password)
        @options = options
        super
      end

      def test?
        ((@options[:test] || @options["test"]) == true) || super
      end

      def authorize(money, creditcard_or_card_id, options = {})
        post = {}
        add_invoice(post, options)
        add_payment_source(post, creditcard_or_card_id, options)
        add_address(post, options)
        commit('P', money, post)
      end

      def purchase(money, creditcard_or_card_id, options = {})
        post = {}
        add_invoice(post, options)
        add_payment_source(post, creditcard_or_card_id, options)
        add_address(post, options)
        post[:moto_ecommerce_ind] = options[:moto_ecommerce_ind] || 7
        commit('D', money, post)
      end

      def capture(money, transaction_id, options = {})
        post ={}
        post[:transaction_id] = transaction_id
        commit('S', money, post)
      end

      # card store will store only the CC number
      # you'll need to pass card_exp_date and cvv2 (if needed)
      def store(creditcard, options = {})
        post = {}
        add_creditcard(post, creditcard, options)
        commit('T', nil, post)
      end

      def unstore(card_id)
        post = {}
        post[:card_id] = card_id
        commit('X', nil, post)
      end

      def credit(money, creditcard_or_card_id, options = {})
        post ={}
        add_payment_source(post, creditcard_or_card_id, options)
        commit('C', money, post)
      end

      def void(transaction_id)
        post = {}
        post[:transaction_id] = transaction_id
        commit('V', nil, post)
      end

      # verify *requires* avs data
      def verify(creditcard_or_card_id, options={})
        post= {}
        add_address(post, options)
        add_payment_source(post, creditcard_or_card_id, options)
        # Must send a value of 0.00 for this transaction type.
        commit('A', 0, post)
      end

      private

      def add_address(post, options)
        if address = options[:billing_address] || options[:address]
          post[:cardholder_street_address] = address[:address1].to_s.gsub(/[^\w.]/, '+')
          post[:cardholder_zip] = address[:zip].to_s
        else
          warn "[#{self.class.name}] Please add the :billing_address to qualify your transaction for preferred interchange!"
        end
      end

      def add_invoice(post, options)
        if options.has_key? :order_id
          post[:invoice_number] = options[:order_id].to_s.gsub(/[^\w.]/, '')
        else
          warn "[#{self.class.name}] Please add the :order_id to qualify your transaction for preferred interchange!"
        end
      end

      def add_payment_source(post, creditcard_or_card_id, options)
        if creditcard_or_card_id.is_a?(String)
          # using stored card
          post[:card_id] = creditcard_or_card_id
          raise ArgumentError.new("[#{self.class.name}] Please provide :card_exp_date=MMYY for a stored card") unless options[:card_exp_date]
          post[:card_exp_date] = options[:card_exp_date]
          post[:cvv2] = options[:cvv2] if options[:cvv2]
        else
          # card info is provided
          add_creditcard(post, creditcard_or_card_id, options)
          post[:card_exp_date] = expdate(creditcard_or_card_id)
          post[:cvv2] = creditcard_or_card_id.verification_value if creditcard_or_card_id.verification_value?
        end
      end

      def add_creditcard(post, creditcard, options)
        post[:card_number]  = creditcard.number
      end

      def parse(body)
        results = {}
        body.split(/&/).each do |pair|
          key,val = pair.split(/=/)
          results[key] = val
        end
        results
      end

      def commit(action, money, parameters)

        url = test? ? TEST_URL : LIVE_URL
        parameters[:transaction_amount]  = amount(money) if money unless action == 'V'

        response = parse( ssl_post(url, post_data(action,parameters)) )
        success_response_code= (action == "A")? "085" : "000"

        Response.new(response["error_code"] == success_response_code, message_from(response, success_response_code), response,
          :authorization => response["transaction_id"],
          :test => test?,
          :cvv_result => response["cvv2_result"],
          :avs_result => { :code => response["avs_result"] }
        )

      end

      def expdate(creditcard)
        year  = sprintf("%.4i", creditcard.year)
        month = sprintf("%.2i", creditcard.month)
        "#{month}#{year[-2..-1]}"
      end

      def message_from(response, success_response_code= "000")
        if response["error_code"] == success_response_code
          "This transaction has been approved"
        else
          response["auth_response_text"]
        end
      end

      def post_data(action, parameters = {})
        post = {}
        post[:profile_id] = @options[:login]
        post[:profile_key] = @options[:password]
        post[:transaction_type] = action if action

        request = post.merge(parameters).map {|key,value| "#{key}=#{CGI.escape(value.to_s)}"}.join("&")
        request
      end
    end

  end
end
