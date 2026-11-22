"""Push notifications: per-device settings, an event outbox, and delivery (SSE for Android, APNs for iOS).

Like the rest of the plugin, hooks (agent process) and routes (dashboard process) share nothing but files under
``<profile dir>/push``. Nothing here logs content, tokens or keys.
"""
