"""Expose ComfyUI node-level progress to the ComfyQueueBar macOS app."""

from __future__ import annotations

from threading import Lock
from typing import Any

from aiohttp import web
from server import PromptServer

import execution
from comfy_execution.progress import ProgressHandler, add_progress_handler


class _QueueBarProgressHandler(ProgressHandler):
    def __init__(self) -> None:
        super().__init__("comfyqueuebar")
        self._lock = Lock()
        self._snapshot: dict[str, Any] = {
            "prompt_id": None,
            "node_id": None,
            "value": None,
            "max": None,
            "percent": None,
            "state": None,
        }

    def _record(self, node_id: str, state: dict[str, Any], prompt_id: str) -> None:
        value = float(state["value"])
        maximum = float(state["max"])
        state_name = getattr(state["state"], "value", str(state["state"]))
        has_fraction = maximum > 0 and (maximum > 1 or value > 0 or state_name == "finished")
        percent = round(min(max(value / maximum * 100, 0), 100), 1) if has_fraction else None
        with self._lock:
            self._snapshot = {
                "prompt_id": prompt_id,
                "node_id": str(node_id),
                "value": value,
                "max": maximum,
                "percent": percent,
                "state": state_name,
            }

    def start_handler(self, node_id: str, state: dict[str, Any], prompt_id: str) -> None:
        self._record(node_id, state, prompt_id)

    def update_handler(
        self,
        node_id: str,
        value: float,
        max_value: float,
        state: dict[str, Any],
        prompt_id: str,
        image: Any = None,
    ) -> None:
        self._record(node_id, state, prompt_id)

    def finish_handler(self, node_id: str, state: dict[str, Any], prompt_id: str) -> None:
        self._record(node_id, state, prompt_id)

    def reset(self) -> None:
        with self._lock:
            self._snapshot = {
                "prompt_id": None,
                "node_id": None,
                "value": None,
                "max": None,
                "percent": None,
                "state": None,
            }

    def snapshot(self) -> dict[str, Any]:
        with self._lock:
            return dict(self._snapshot)


_progress_handler = _QueueBarProgressHandler()
_original_reset_progress_state = execution.reset_progress_state


def _reset_progress_state_with_queue_bar(prompt_id: str, dynprompt: Any) -> None:
    _progress_handler.reset()
    _original_reset_progress_state(prompt_id, dynprompt)
    add_progress_handler(_progress_handler)


# ComfyUI creates a fresh registry for each prompt. Register after each reset so
# this observer follows the active workflow without taking over its WebSocket.
execution.reset_progress_state = _reset_progress_state_with_queue_bar


@PromptServer.instance.routes.get("/comfyqueuebar/queue-progress")
async def _queue_bar_progress(_: web.Request) -> web.Response:
    return web.json_response(_progress_handler.snapshot())


NODE_CLASS_MAPPINGS: dict[str, Any] = {}
NODE_DISPLAY_NAME_MAPPINGS: dict[str, str] = {}
