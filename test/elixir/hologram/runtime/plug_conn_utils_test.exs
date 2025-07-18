defmodule Hologram.Runtime.PlugConnUtilsTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Runtime.PlugConnUtils
  alias Hologram.Runtime.Cookie

  describe "extract_cookies/1" do
    test "extracts cookies from Plug.Conn struct with cookies" do
      conn = %Plug.Conn{
        cookies: %{"user_id" => "abc123", "theme" => "dark"},
        req_cookies: %{"user_id" => "abc123", "theme" => "dark"}
      }

      result = extract_cookies(conn)

      assert result == %{"user_id" => "abc123", "theme" => "dark"}
    end

    test "extracts cookies from Plug.Conn struct with no cookies" do
      conn = %Plug.Conn{cookies: %{}, req_cookies: %{}}

      result = extract_cookies(conn)

      assert result == %{}
    end

    test "fetches cookies from Plug.Conn struct that hasn't been processed yet" do
      # This simulates a Plug.Conn struct that hasn't had fetch_cookies/1 called on it.
      # The actual cookies must be fetched from headers.
      conn = %Plug.Conn{
        cookies: %Plug.Conn.Unfetched{aspect: :cookies},
        req_cookies: %Plug.Conn.Unfetched{aspect: :cookies},
        req_headers: [
          {"cookie", "user_id=abc123; theme=dark"}
        ]
      }

      result = extract_cookies(conn)

      assert result == %{"user_id" => "abc123", "theme" => "dark"}
    end

    test "excludes hologram_session cookie" do
      conn = %Plug.Conn{
        cookies: %{
          "user_id" => "abc123",
          "theme" => "dark",
          "hologram_session" => "session_data_xyz789"
        },
        req_cookies: %{
          "user_id" => "abc123",
          "theme" => "dark",
          "hologram_session" => "session_data_xyz789"
        }
      }

      result = extract_cookies(conn)

      refute Map.has_key?(result, "hologram_session")
    end

    test "decodes cookie values using Cookie.decode/1" do
      encoded_map = Cookie.encode(%{key: "value"})

      conn = %Plug.Conn{
        cookies: %{
          "plain_cookie" => "plain_value",
          "encoded_cookie" => encoded_map
        },
        req_cookies: %{
          "plain_cookie" => "plain_value",
          "encoded_cookie" => encoded_map
        }
      }

      result = extract_cookies(conn)

      assert result["plain_cookie"] == "plain_value"
      assert result["encoded_cookie"] == %{key: "value"}
    end
  end
end
