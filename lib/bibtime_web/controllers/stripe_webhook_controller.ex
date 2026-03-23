defmodule BibtimeWeb.StripeWebhookController do
  use BibtimeWeb, :controller

  require Logger

  alias Bibtime.Payments

  @doc """
  Handles incoming Stripe webhook events.
  Verifies the webhook signature before processing.
  """
  def create(conn, _params) do
    with {:ok, payload} <- get_raw_body(conn),
         {:ok, event} <- verify_webhook(payload, conn) do
      handle_event(event)

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(%{received: true}))
    else
      {:error, reason} ->
        Logger.warning("Stripe webhook error: #{inspect(reason)}")

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: "Webhook verification failed"}))
    end
  end

  defp get_raw_body(conn) do
    case conn.assigns[:raw_body] do
      nil -> {:error, :no_raw_body}
      body -> {:ok, body}
    end
  end

  defp verify_webhook(payload, conn) do
    signature = List.first(Plug.Conn.get_req_header(conn, "stripe-signature"))
    signing_secret = Application.get_env(:stripity_stripe, :signing_secret)

    cond do
      is_nil(signature) ->
        {:error, :missing_signature}

      is_nil(signing_secret) or signing_secret == "" ->
        Logger.warning("Stripe webhook signing secret not configured")
        {:error, :missing_signing_secret}

      true ->
        case Stripe.Webhook.construct_event(payload, signature, signing_secret) do
          {:ok, event} -> {:ok, event}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp handle_event(%{type: "checkout.session.completed"} = event) do
    session_id = event.data.object.id
    Logger.info("Stripe checkout.session.completed: #{session_id}")

    case Payments.handle_checkout_completed(session_id) do
      {:ok, _payment} -> :ok
      {:error, reason} -> Logger.error("Failed to process checkout: #{inspect(reason)}")
    end
  end

  defp handle_event(%{type: "charge.refunded"} = event) do
    payment_intent_id = event.data.object.payment_intent
    Logger.info("Stripe charge.refunded for payment_intent: #{payment_intent_id}")

    case Payments.handle_charge_refunded(payment_intent_id) do
      {:ok, _payment} -> :ok
      {:error, reason} -> Logger.error("Failed to process refund: #{inspect(reason)}")
    end
  end

  defp handle_event(%{type: type}) do
    Logger.debug("Unhandled Stripe event: #{type}")
    :ok
  end
end
