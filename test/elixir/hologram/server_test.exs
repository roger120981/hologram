defmodule Hologram.ServerTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Server
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Component.Action
  alias Hologram.Runtime.Cookie
  alias Hologram.Server
  alias Hologram.Server.Metadata

  use_module_stub :server

  setup :set_mox_global

  # Must be defined after setting up Server stub.
  @timestamp ServerStub.timestamp()

  setup do
    setup_server(ServerStub)
  end

  describe "delete_cookie/2" do
    test "removes an existing cookie from the server struct" do
      server = %Server{cookies: %{"user_id" => "123", "theme" => "dark"}}

      result = delete_cookie(server, "user_id")

      assert result.cookies == %{"theme" => "dark"}
      assert result.__meta__.cookie_ops["user_id"] == {:delete, @timestamp}
    end

    test "handles deleting a nonexistent cookie as no-op" do
      server = %Server{cookies: %{"theme" => "dark"}}

      result = delete_cookie(server, "nonexistent")

      assert result == server
    end

    test "handles deleting from empty cookies map as no-op" do
      server = %Server{cookies: %{}}

      result = delete_cookie(server, "any_key")

      assert result == server
    end

    test "preserves existing metadata cookie_ops when deleting" do
      server = %Server{
        cookies: %{"user_id" => "123", "theme" => "dark"},
        __meta__: %Metadata{
          cookie_ops: %{
            "existing_op" => {:put, @timestamp - 1, %Cookie{value: "some_value"}}
          }
        }
      }

      result = delete_cookie(server, "user_id")

      assert result.cookies == %{"theme" => "dark"}
      assert result.__meta__.cookie_ops["user_id"] == {:delete, @timestamp}

      assert result.__meta__.cookie_ops["existing_op"] ==
               {:put, @timestamp - 1, %Cookie{value: "some_value"}}
    end

    test "preserves existing metadata when deleting nonexistent cookie" do
      server = %Server{
        cookies: %{"theme" => "dark"},
        __meta__: %Metadata{
          cookie_ops: %{
            "existing_op" => {:put, @timestamp - 1, %Cookie{value: "some_value"}}
          }
        }
      }

      result = delete_cookie(server, "nonexistent")

      assert result == server
    end

    test "overwrites existing cookie operation when same key is deleted" do
      server = %Server{
        cookies: %{"user_id" => "123"},
        __meta__: %Metadata{
          cookie_ops: %{
            "user_id" => {:put, @timestamp - 1, %Cookie{value: "123"}}
          }
        }
      }

      result = delete_cookie(server, "user_id")

      assert result.cookies == %{}
      assert result.__meta__.cookie_ops["user_id"] == {:delete, @timestamp}
    end

    test "preserves other server struct fields unchanged" do
      server = %Server{
        cookies: %{"user_id" => "123"},
        next_action: %Action{name: :some_action}
      }

      result = delete_cookie(server, "user_id")

      assert result.next_action == %Action{name: :some_action}
    end
  end

  describe "diff_cookies/2" do
    test "extracts cookies from both servers and delegates to MapUtils.diff/2" do
      server_1 = %Server{cookies: %{"user_id" => 123, "theme" => "light"}}
      server_2 = %Server{cookies: %{"user_id" => 456, "lang" => "en"}}

      result = diff_cookies(server_1, server_2)

      assert result == %{
               added: [{"lang", "en"}],
               removed: ["theme"],
               edited: [{"user_id", 456}]
             }
    end
  end

  describe "from/1" do
    test "creates Server struct from Plug.Conn struct" do
      conn = %Plug.Conn{
        cookies: %{"user_id" => "abc123", "theme" => "dark"},
        req_cookies: %{"user_id" => "abc123", "theme" => "dark"}
      }

      result = from(conn)

      assert result == %Server{cookies: %{"user_id" => "abc123", "theme" => "dark"}}
    end

    test "excludes hologram_session cookie from server cookies" do
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

      result = from(conn)

      refute Map.has_key?(result.cookies, "hologram_session")
    end
  end

  describe "get_cookie/2" do
    test "returns the value of an existing cookie" do
      server = %Server{cookies: %{"user_id" => "abc123", "theme" => "dark"}}

      result = get_cookie(server, "user_id")

      assert result == "abc123"
    end

    test "returns nil for a nonexistent cookie" do
      server = %Server{cookies: %{"user_id" => "abc123"}}

      result = get_cookie(server, "nonexistent")

      assert result == nil
    end

    test "returns nil when cookies map is empty" do
      server = %Server{cookies: %{}}

      result = get_cookie(server, "any_key")

      assert result == nil
    end

    test "returns custom default for a nonexistent cookie" do
      server = %Server{cookies: %{"user_id" => "abc123"}}

      result = get_cookie(server, "nonexistent", "default_value")

      assert result == "default_value"
    end

    test "returns custom default when cookies map is empty" do
      server = %Server{cookies: %{}}

      result = get_cookie(server, "any_key", "fallback")

      assert result == "fallback"
    end

    test "returns actual value over default when cookie exists" do
      server = %Server{cookies: %{"theme" => "dark"}}

      result = get_cookie(server, "theme", "light")

      assert result == "dark"
    end
  end

  describe "get_cookie_ops/1" do
    test "returns cookie operations recorded in the server struct's metadata" do
      server = %Server{cookies: %{"existing_cookie" => "value"}}

      new_server =
        server
        |> put_cookie("new_cookie", "new_value")
        |> delete_cookie("existing_cookie")

      result = get_cookie_ops(new_server)

      assert result == %{
               "new_cookie" => {:put, @timestamp, %Cookie{value: "new_value"}},
               "existing_cookie" => {:delete, @timestamp}
             }
    end
  end

  describe "has_cookie_ops?/1" do
    test "returns false when no cookie operations have been recorded" do
      server = %Server{cookies: %{"user_id" => "123"}}

      result = has_cookie_ops?(server)

      assert result == false
    end

    test "returns true when put operation has been recorded" do
      server = put_cookie(%Server{}, "theme", "dark")

      result = has_cookie_ops?(server)

      assert result == true
    end

    test "returns true when delete operation has been recorded" do
      server = %Server{cookies: %{"theme" => "dark"}}
      new_server = delete_cookie(server, "theme")

      result = has_cookie_ops?(new_server)

      assert result == true
    end

    test "returns true when multiple operations have been recorded" do
      server = %Server{cookies: %{"user_id" => "123", "theme" => "dark"}}

      new_server =
        server
        |> put_cookie("lang", "en")
        |> delete_cookie("user_id")

      result = has_cookie_ops?(new_server)

      assert result == true
    end
  end

  describe "put_cookie/4" do
    test "adds a cookie with default options" do
      result = put_cookie(%Server{}, "my_cookie", "abc123")

      expected_cookie = %Cookie{
        value: "abc123",
        domain: nil,
        http_only: true,
        max_age: nil,
        path: nil,
        same_site: :lax,
        secure: true
      }

      assert result.cookies["my_cookie"] == "abc123"
      assert result.__meta__.cookie_ops["my_cookie"] == {:put, @timestamp, expected_cookie}
    end

    test "adds a cookie with custom options" do
      opts = [
        domain: "example.com",
        http_only: false,
        max_age: 3_600,
        path: "/app",
        same_site: :strict,
        secure: false
      ]

      result = put_cookie(%Server{}, "my_cookie", "abc123", opts)

      expected_cookie = %Cookie{
        value: "abc123",
        domain: "example.com",
        http_only: false,
        max_age: 3_600,
        path: "/app",
        same_site: :strict,
        secure: false
      }

      assert result.cookies["my_cookie"] == "abc123"
      assert result.__meta__.cookie_ops["my_cookie"] == {:put, @timestamp, expected_cookie}
    end

    test "adds multiple cookies to existing server struct" do
      server = %Server{cookies: %{"existing" => "old"}}

      result =
        server
        |> put_cookie("first", "value_1")
        |> put_cookie("second", "value_2")

      assert result == %Server{
               cookies: %{
                 "existing" => "old",
                 "first" => "value_1",
                 "second" => "value_2"
               },
               __meta__: %Metadata{
                 cookie_ops: %{
                   "first" => {:put, @timestamp, %Cookie{value: "value_1"}},
                   "second" => {:put, @timestamp, %Cookie{value: "value_2"}}
                 }
               }
             }
    end

    test "overwrites existing cookie with same key" do
      server = %Server{
        cookies: %{"theme" => "light"},
        __meta__: %Metadata{
          cookie_ops: %{
            "theme" => {:put, @timestamp, %Cookie{value: "light"}}
          }
        }
      }

      result = put_cookie(server, "theme", "dark")

      assert result == %Server{
               cookies: %{"theme" => "dark"},
               __meta__: %Metadata{
                 cookie_ops: %{
                   "theme" => {:put, @timestamp, %Cookie{value: "dark"}}
                 }
               }
             }
    end

    test "supports different value types" do
      result =
        %Server{}
        |> put_cookie("string", "text")
        |> put_cookie("integer", 42)
        |> put_cookie("boolean", true)
        |> put_cookie("list", [1, 2, 3])

      cookies = result.cookies
      assert cookies["string"] == "text"
      assert cookies["integer"] == 42
      assert cookies["boolean"] == true
      assert cookies["list"] == [1, 2, 3]

      cookie_ops = result.__meta__.cookie_ops
      assert cookie_ops["string"] == {:put, @timestamp, %Cookie{value: "text"}}
      assert cookie_ops["integer"] == {:put, @timestamp, %Cookie{value: 42}}
      assert cookie_ops["boolean"] == {:put, @timestamp, %Cookie{value: true}}
      assert cookie_ops["list"] == {:put, @timestamp, %Cookie{value: [1, 2, 3]}}
    end

    test "raises ArgumentError when key is not a string" do
      expected_msg = """
      Cookie key must be a string, but received :abc.

      Cookie keys must be strings according to web standards.
      Try converting your key to a string: "abc".\
      """

      assert_error ArgumentError, expected_msg, fn ->
        put_cookie(%Server{}, :abc, "value")
      end
    end

    test "raises KeyError when invalid option is given" do
      assert_error KeyError, "key :invalid_opt not found", fn ->
        put_cookie(%Server{}, "abc", :value, invalid_opt: 123)
      end
    end

    test "partial options override defaults" do
      result = put_cookie(%Server{}, "my_cookie", "abc123", secure: false, path: "/app")

      expected_cookie = %Cookie{
        value: "abc123",
        domain: nil,
        http_only: true,
        max_age: nil,
        path: "/app",
        same_site: :lax,
        secure: false
      }

      assert result.cookies == %{"my_cookie" => "abc123"}
      assert result.__meta__.cookie_ops["my_cookie"] == {:put, @timestamp, expected_cookie}
    end
  end
end
