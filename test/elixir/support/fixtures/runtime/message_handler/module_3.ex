defmodule Hologram.Test.Fixtures.Runtime.MessageHandler.Module3 do
  use Hologram.Page

  route "/hologram-test-fixtures-runtime-message-handler-module3/:a/:b"

  param :a, :integer
  param :b, :integer

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO"page Module3 template, params: a = {@a}, b = {@b}"
  end
end
