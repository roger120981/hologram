defmodule Hologram.RouterTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Router
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Commons.ETS
  alias Hologram.Test.Fixtures.Router.Module1

  use_module_stub :page_digest_registry
  use_module_stub :page_module_resolver

  setup :set_mox_global

  setup do
    setup_page_digest_registry(PageDigestRegistryStub)
    setup_page_module_resolver(PageModuleResolverStub)
  end

  describe "regular HTTP requests" do
    test "request path is matched" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module1, :dummy_module_1_digest)

      conn =
        :get
        |> Plug.Test.conn("/hologram-test-fixtures-router-module1")
        |> Plug.Conn.fetch_cookies()
        |> call([])

      assert conn.halted == true
      assert conn.resp_body == "page Hologram.Test.Fixtures.Router.Module1 template"
      assert conn.state == :sent
      assert conn.status == 200
    end

    test "request path is not matched" do
      conn =
        :get
        |> Plug.Test.conn("/my-unmatched-request-path")
        |> Plug.Conn.fetch_cookies()
        |> call([])

      assert conn.halted == false
      assert conn.resp_body == nil
      assert conn.state == :unset
      assert conn.status == nil
    end
  end

  test "websocket upgrade request" do
    conn =
      :get
      |> Plug.Test.conn("/hologram/websocket")
      |> Map.put(:req_headers, [
        {"host", "localhost"},
        {"upgrade", "websocket"},
        {"connection", "Upgrade"},
        {"sec-websocket-key", "dGhlIHNhbXBsZSBub25jZQ=="},
        {"sec-websocket-version", "13"}
      ])
      |> call([])

    assert conn.halted == true
    assert conn.state == :upgraded

    # Note: In production, WebSocket upgrades should set status to 101 (Switching Protocols),
    # but Plug.Adapters.Test.Conn.upgrade/3 doesn't simulate this HTTP protocol behavior.
    # The :upgraded state confirms the upgrade was processed correctly in the test environment.
    assert conn.status == nil
  end
end
