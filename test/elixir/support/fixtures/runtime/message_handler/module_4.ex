defmodule Hologram.Test.Fixtures.Runtime.MessageHandler.Module4 do
  use Hologram.Component
  alias Hologram.UI.Runtime

  @impl Component
  def template do
    ~HOLO"""
    <html>
      <head>
        <Runtime />
      </head>
      <body>
        <slot />
      </body>
    </html>
    """
  end
end
