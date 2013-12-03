require 'idevice/c'
require 'idevice/idevice'
require 'idevice/lockdown'
require 'idevice/plist'

module Idevice
  class HouseArrestError < IdeviceLibError
  end

  class HouseArrestClient < C::ManagedOpaquePointer
    include LibHelpers

    def self.release(ptr)
      C.house_arrest_client_free(ptr) unless ptr.null?
    end

    def self.attach(opts={})
      _attach_helper("com.apple.mobile.house_arrest", opts) do |idevice, ldsvc, p_ha|
        err = C.house_arrest_client_new(idevice, ldsvc, p_ha)
        raise HouseArrestError, "house_arrest error: #{err}" if err != :SUCCESS
        ha = p_ha.read_pointer
        raise HouseArrestError, "house_arrest_client_new returned a NULL house_arrest_client_t pointer" if ha.null?
        return new(ha)
      end
    end

    def send_request(dict)
      err = C.house_arrest_send_request(self, dict.to_plist_t)
      raise HouseArrestError, "house_arrest error: #{err}" if err != :SUCCESS
      return true
    end

    def send_command(command, appid)
      err = C.house_arrest_send_command(self, command, appid)
      raise HouseArrestError, "house_arrest error: #{err}" if err != :SUCCESS
      return true
    end

    def get_result
      FFI::MemoryPointer.new(:pointer) do |p_result|
        err = C.house_arrest_get_result(self, p_result)
        raise HouseArrestError, "house_arrest error: #{err}" if err != :SUCCESS
        result = p_result.read_pointer
        raise HouseArrestError, "house_arrest_get_result returned a null plist_t" if result.null?
        return Plist_t.new(result).to_ruby
      end
    end

    def vend_container(appid)
      send_command("VendContainer", appid)
      res = get_result
      if res["Error"]
        raise HouseArrestError, "Error vending container to appid: #{appid} - #{res.inspect}"
      end
    end

    def vend_documents(appid)
      send_command("VendDocuments", appid)
      res = get_result
      if res["Error"]
        raise HouseArrestError, "Error vending documents to appid: #{appid} - #{res.inspect}"
      end
    end

    def afc_client
      FFI::MemoryPointer.new(:pointer) do |p_afc|
        err = C.afc_client_new_from_house_arrest_client(self, p_afc)
        raise AFCError, "AFC Error: #{err}" if err != :SUCCESS
        afc = p_afc.read_pointer
        raise AFCError, "afc_client_new_from_house_arrest_client returned a NULL afc_client_t pointer" if afc.null?
        cli =  AFCClient.new(afc)

        # save a reference to ourselves in the afc client to avoid premature garbage collection...
        cli.instance_variable_set(:@house_arrest, self)
        return cli
      end
    end

    def afc_client_for_container(appid)
      vend_container(appid)
      return afc_client
    end

    def afc_client_for_documents(appid)
      vend_documents(appid)
      return afc_client
    end
  end

  module C
    ffi_lib 'imobiledevice'

    typedef enum(
      :SUCCESS          ,     0,
      :INVALID_ARG      ,    -1,
      :PLIST_ERROR      ,    -2,
      :CONN_FAILED      ,    -3,
      :INVALID_MODE     ,    -4,
      :UNKNOWN_ERROR    ,  -256,
    ), :house_arrest_error_t

    #house_arrest_error_t house_arrest_client_new(idevice_t device, lockdownd_service_descriptor_t service, house_arrest_client_t *client);
    attach_function :house_arrest_client_new, [Idevice, LockdownServiceDescriptor, :pointer], :house_arrest_error_t

    #house_arrest_error_t house_arrest_client_free(house_arrest_client_t client);
    attach_function :house_arrest_client_free, [HouseArrestClient], :house_arrest_error_t

    #house_arrest_error_t house_arrest_send_request(house_arrest_client_t client, plist_t dict);
    attach_function :house_arrest_send_request, [HouseArrestClient, Plist_t], :house_arrest_error_t

    #house_arrest_error_t house_arrest_send_command(house_arrest_client_t client, const char *command, const char *appid);
    attach_function :house_arrest_send_command, [HouseArrestClient, :string, :string], :house_arrest_error_t

    #house_arrest_error_t house_arrest_get_result(house_arrest_client_t client, plist_t *dict);
    attach_function :house_arrest_get_result, [HouseArrestClient, :pointer], :house_arrest_error_t

  end
end