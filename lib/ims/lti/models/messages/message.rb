module IMS::LTI::Models::Messages
  class Message
    class << self

      def required_params
        supers_params('@required_params') | (@required_params || [])
      end

      def add_required_params(param, *params)
        add_params('@required_params', param, *params)
      end

      def recommended_params
        supers_params('@recommended_params') | (@recommended_params || [])
      end

      def add_recommended_params(param, *params)
        add_params('@recommended_params', param, *params)
      end

      def optional_params
        supers_params('@optional_params') | (@optional_params || [])
      end

      def add_optional_params(param, *params)
        add_params('@optional_params', param, *params)
      end

      def deprecated_params
        supers_params('@deprecated_params') | (@deprecated_params || [])
      end

      def add_deprecated_params(param, *params)
        add_params('@deprecated_params', param, *params)
      end

      private

      def add_params(instance_variable, param, *params)
        instance_var = self.instance_variable_get(instance_variable) || []
        instance_var |= params.unshift(param)
        self.instance_variable_set(instance_variable, instance_var)
        attr_accessor(params.shift, *params)
      end

      def parameters
        required_params + recommended_params + optional_params + deprecated_params
      end

      def supers_params(instance_variable)
        superclass == Object ? [] : superclass.instance_variable_get(instance_variable) || []
      end

    end

    LAUNCH_TARGET_IFRAME = 'iframe'
    LAUNCH_TARGET_WINDOW = 'window'

    EXTENSION_PREFIX = 'ext_'
    CUSTOM_PREFIX = 'custom_'

    OAUTH_KEYS = :oauth_callback, :oauth_consumer_key, :oauth_nonce, :oauth_signature, :oauth_signature_method,
      :oauth_timestamp, :oauth_token, :oauth_verifier, :oauth_version

    attr_accessor :launch_url, *OAUTH_KEYS

    add_required_params :lti_message_type, :lti_version
    add_recommended_params :user_id, :roles, :launch_presentation_document_target, :launch_presentation_width, :launch_presentation_height
    add_optional_params :launch_presentation_local, :launch_presentation_css_url

    def initialize(attrs = {})

      @custom_params = {}
      @ext_params = {}

      attrs.each do |k, v|
        str_key = k.to_s
        if str_key.start_with?(EXTENSION_PREFIX)
          @ext_params[str_key] = v
        elsif str_key.start_with?(CUSTOM_PREFIX)
          @custom_params[str_key] = v
        elsif !v.nil? && self.respond_to?(k.to_sym)
          instance_variable_set("@#{k}", v)
        else
          warn "Unknown parameter #{k}"
        end
      end
    end

    def add_custom_params(params)
      params.each { |k, v| k.to_s.start_with?('custom_') ? @custom_params[k.to_s] = v : @custom_params["custom_#{k.to_s}"] = v }
    end

    def get_custom_params
      @custom_params.inject({}) { |hash, (k, v)| hash[k.gsub(/\Acustom_/, '')] = v; hash }
    end

    def post_params
      @custom_params.merge(@ext_params).merge(parameters)
    end

    def signed_post_params(secret)
      params = post_params
      header = SimpleOAuth::Header.new(:post, launch_url, params, consumer_key: oauth_consumer_key, consumer_secret: secret)
      header.signed_attributes.merge(params)
    end

    def valid_signature?(secret)
      params = OAUTH_KEYS.inject({}) do |hash, k|
        value = instance_variable_get("@#{k}")
        hash[k] = value if value
        hash
      end
      options, parsed_params = parse_params(params.merge(post_params))
      signature = parsed_params.delete(:oauth_signature)
      consumer_key = oauth_consumer_key
      header = SimpleOAuth::Header.new(:post, launch_url, parsed_params, options.merge({consumer_key: consumer_key, consumer_secret: secret}))
      header.valid?(signature: signature)
    end

    def method_missing(meth, *args, &block)
      if match = /^(custom|ext)_([^=$]*)/.match(meth)
        param_type, key = match.captures
        param_hash = instance_variable_get("@#{param_type}_params".to_sym)
        meth =~ /=$/ ? param_hash[match.to_s] = args[0] : param_hash[match.to_s]
      else
        super
      end
    end

    private

    def parameters
      self.class.send("parameters").inject({}) do |h, param|
        value = instance_variable_get("@#{param.to_s}")
        h[param.to_s] = value unless value.nil?
        h
      end
    end

    def parse_params(params)
      params.inject([{}, {}]) do |array, (k, v)|
        attr = k.to_s.sub('oauth_', '').to_sym
        if SimpleOAuth::Header::ATTRIBUTE_KEYS.include?(attr)
          array[0][attr] = v
        else
          array[1][k] = v
        end
        array
      end
    end

  end
end