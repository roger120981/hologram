"use strict";

import GlobalRegistry from "./global_registry.mjs";
import LiveReload from "./live_reload.mjs";
import Serializer from "./serializer.mjs";

export default class Connection {
  // 1 second
  static BASE_RECONNECT_DELAY = 1_000;

  // 10 seconds
  static CONNECTION_TIMEOUT = 10_000;

  // 32 seconds
  static MAX_RECONNECT_DELAY = 32_000;

  // 30 seconds
  static PING_INTERVAL = 30_000;

  // 5 seconds
  static PONG_TIMEOUT = 5_000;

  // 60 seconds
  static REQUEST_TIMEOUT = 60_000;

  static WEBSOCKET_PATH = "/hologram/websocket";

  static connectionTimer = null;
  static pendingRequests = new Map();
  static pingTimer = null;
  static pongTimer = null;
  static reconnectAttempts = 0;
  static reconnectTimer = null;
  static websocket = null;

  // disconnected, connecting, connected, error
  static status = "disconnected";

  static clearConnectionTimer() {
    if ($.connectionTimer) {
      clearTimeout($.connectionTimer);
      $.connectionTimer = null;
    }
  }

  static clearPendingRequests(triggerErrorCallbacks) {
    for (const [_correlationId, request] of $.pendingRequests.entries()) {
      clearTimeout(request.timerId);

      if (triggerErrorCallbacks) {
        request.onError();
      }
    }

    $.pendingRequests.clear();
  }

  static clearPingTimer() {
    if ($.pingTimer) {
      clearInterval($.pingTimer);
      $.pingTimer = null;
    }
  }

  static clearPongTimer() {
    if ($.pongTimer) {
      clearTimeout($.pongTimer);
      $.pongTimer = null;
    }
  }

  static clearReconnectTimer() {
    if ($.reconnectTimer) {
      clearTimeout($.reconnectTimer);
      $.reconnectTimer = null;
    }
  }

  static connect() {
    if ($.status === "connected" || $.status === "connecting") return;

    $.status = "connecting";
    $.clearReconnectTimer();

    try {
      $.websocket = new WebSocket($.WEBSOCKET_PATH);

      $.websocket.onopen = $.handleOpen;
      $.websocket.onclose = $.handleClose;
      $.websocket.onerror = $.handleError;
      $.websocket.onmessage = $.handleMessage;

      $.connectionTimer = setTimeout(() => {
        if ($.status === "connecting") {
          $.websocket.close();
          $.handleConnectionTimeout();
        }
      }, $.CONNECTION_TIMEOUT);
    } catch (error) {
      $.handleError(error);
    }
  }

  static encodeMessage(type, payload, correlationId) {
    if (payload === null && correlationId === null) return `"${type}"`;

    if (correlationId) {
      return `["${type}",${Serializer.serialize(payload, "server")},"${correlationId}"]`;
    }

    return `["${type}",${Serializer.serialize(payload, "server")}]`;
  }

  static handleClose(event) {
    console.warn("Hologram: disconnected from server", event);

    $.status = "disconnected";
    GlobalRegistry.set("connected?", false);

    $.clearConnectionTimer();
    $.clearPingTimer();
    $.clearPongTimer();
    $.clearPendingRequests(true);

    $.reconnect();
  }

  static handleConnectionTimeout() {
    console.error("Hologram: server connection timeout");

    $.status = "error";

    $.reconnect();
  }

  static handleError(event) {
    console.error("Hologram: server connection error", event);

    $.status = "error";
    GlobalRegistry.set("connected?", false);

    $.clearConnectionTimer();

    $.reconnect();
  }

  static handleMessage(event) {
    const encodedMessage = event.data;

    if (encodedMessage === '"pong"') {
      $.clearPongTimer();
      return;
    }

    if (encodedMessage === '"reload"') {
      document.location.reload();
      return;
    }

    const decodedMessage = JSON.parse(encodedMessage);

    if (decodedMessage.length === 3) {
      // Currently, the only supported message type that has a correlation ID is "reply"
      const [_type, payload, correlationId] = decodedMessage;

      if ($.pendingRequests.has(correlationId)) {
        const request = $.pendingRequests.get(correlationId);

        clearTimeout(request.timerId);
        $.pendingRequests.delete(correlationId);

        request.onSuccess(payload);
      }

      return;
    }

    // Currently, the only supported message type that has a payload,
    // but doesn't have a correlation ID is "compilation_error"
    const [_type, payload] = decodedMessage;
    LiveReload.showErrorOverlay(payload);
  }

  static handleOpen(_event) {
    console.log("Hologram: connected to server");

    $.status = "connected";
    GlobalRegistry.set("connected?", true);

    $.reconnectAttempts = 0;
    $.clearConnectionTimer();

    $.startPing();
  }

  static isConnected() {
    return $.status === "connected";
  }

  static reconnect() {
    $.reconnectAttempts++;

    const delay = Math.min(
      $.BASE_RECONNECT_DELAY * Math.pow(2, $.reconnectAttempts - 1),
      $.MAX_RECONNECT_DELAY,
    );

    console.log(
      `Hologram: reconnecting in ${delay} ms (attempt ${$.reconnectAttempts})`,
    );

    $.reconnectTimer = setTimeout(() => {
      $.connect();
    }, delay);
  }

  static sendMessage(type, payload = null, correlationId = null) {
    if ($.status === "connected") {
      const encodedMessage = $.encodeMessage(type, payload, correlationId);

      try {
        $.websocket.send(encodedMessage);
        return true;
        // eslint-disable-next-line no-empty
      } catch {}
    }

    console.error(
      "Hologram: failed to send message to server",
      type,
      payload,
      correlationId,
    );

    return false;
  }

  static sendRequest(
    type,
    payload = null,
    {onSuccess, onError, onTimeout, timeout = $.REQUEST_TIMEOUT} = {},
  ) {
    return new Promise((resolve, reject) => {
      const correlationId = crypto.randomUUID();

      const timerId = setTimeout(() => {
        $.pendingRequests.delete(correlationId);
        if (onTimeout) onTimeout();
        reject(new Error("Request timeout"));
      }, timeout);

      $.pendingRequests.set(correlationId, {
        onSuccess: (responsePayload) => {
          if (onSuccess) onSuccess(responsePayload);
          resolve(responsePayload);
        },
        onError: () => {
          if (onError) onError();
          reject(new Error("Request failed"));
        },
        onTimeout: () => {
          if (onTimeout) onTimeout();
          reject(new Error("Request timeout"));
        },
        timerId,
      });

      if (!$.sendMessage(type, payload, correlationId)) {
        $.pendingRequests.delete(correlationId);
        clearTimeout(timerId);
        if (onError) onError();
        reject(new Error("Failed to send message"));
      }
    });
  }

  static sendPing() {
    if ($.status === "connected") {
      $.sendMessage("ping");

      $.pongTimer = setTimeout(() => {
        console.warn("Hologram: pong timeout");
        $.websocket.close();
      }, $.PONG_TIMEOUT);
    }
  }

  static startPing() {
    $.clearPingTimer();

    $.pingTimer = setInterval(() => {
      if ($.status === "connected") {
        $.sendPing();
      }
    }, $.PING_INTERVAL);
  }
}

const $ = Connection;
