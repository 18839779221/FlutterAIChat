#!/usr/bin/env python3

from __future__ import annotations

import asyncio
import os
import subprocess
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from types import SimpleNamespace
from xml.etree import ElementTree


@dataclass
class ButtonTarget:
    index: int
    left: int
    top: int
    right: int
    bottom: int

    @property
    def center_x(self) -> int:
        return (self.left + self.right) // 2

    @property
    def center_y(self) -> int:
        return (self.top + self.bottom) // 2


def _element_texts(element: dict) -> list[str]:
    return [
        str(value).strip()
        for value in (
            element.get("text"),
            element.get("contentDescription"),
            element.get("content-desc"),
            element.get("label"),
            element.get("hintText"),
        )
        if value is not None and str(value).strip()
    ]


def _element_matches_any_text(element: dict, candidates: set[str]) -> bool:
    return any(text in candidates for text in _element_texts(element))


def _element_contains_any_text(element: dict, candidates: set[str]) -> bool:
    return any(any(candidate in text for candidate in candidates) for text in _element_texts(element))


def parse_bounds(bounds: str) -> tuple[int, int, int, int]:
    left, top, right, bottom = (int(part) for part in bounds.split(","))
    return left, top, right, bottom


def _target_from_element(element: dict) -> ButtonTarget:
    bounds = element.get("bounds")
    if not bounds:
        raise RuntimeError(f"Element is missing bounds: {element}")

    left, top, right, bottom = parse_bounds(bounds)
    return ButtonTarget(
        index=element.get("index", -1),
        left=left,
        top=top,
        right=right,
        bottom=bottom,
    )


def find_chat_input_target(ui_state) -> ButtonTarget:
    semantic_candidates: list[ButtonTarget] = []
    fallback_candidates: list[ButtonTarget] = []

    for element in ui_state.elements:
        if element.get("className") != "EditText":
            continue

        target = _target_from_element(element)
        if _element_contains_any_text(
            element,
            {"聊天输入框", "输入消息", "继续提问", "tool", "message", "prompt"},
        ):
            semantic_candidates.append(target)
            continue

        fallback_candidates.append(target)

    if semantic_candidates:
        return sorted(semantic_candidates, key=lambda item: (item.bottom, item.right))[-1]

    if fallback_candidates:
        return sorted(fallback_candidates, key=lambda item: (item.bottom, item.right))[-1]

    raise RuntimeError("Unable to locate chat input field")


def parse_uiautomator_dump(xml_text: str):
    root = ElementTree.fromstring(xml_text)
    elements: list[dict] = []
    screen_width = 0
    screen_height = 0

    for node in root.iter("node"):
        bounds = node.attrib.get("bounds")
        if not bounds:
            continue

        normalized_bounds = bounds.strip("[]").replace("][", ",")
        left, top, right, bottom = parse_bounds(normalized_bounds)
        screen_width = max(screen_width, right)
        screen_height = max(screen_height, bottom)
        class_name = node.attrib.get("class", "").split(".")[-1]
        elements.append(
            {
                "index": int(node.attrib.get("index", "-1")),
                "className": class_name,
                "bounds": normalized_bounds,
                "text": node.attrib.get("text", ""),
                "contentDescription": node.attrib.get("content-desc", ""),
            },
        )

    return SimpleNamespace(
        elements=elements,
        screen_width=screen_width,
        screen_height=screen_height,
        phone_state={"packageName": os.environ.get("APP_PACKAGE", "com.example.ai_chat")},
    )


def _fetch_uiautomator_state(serial: str):
    dump_result = subprocess.run(
        ["adb", "-s", serial, "shell", "uiautomator", "dump", "/sdcard/window_dump.xml"],
        check=True,
        capture_output=True,
        text=True,
    )
    if dump_result.returncode != 0:
        raise RuntimeError(f"uiautomator dump failed: {dump_result.stderr}")

    xml_result = subprocess.run(
        ["adb", "-s", serial, "shell", "cat", "/sdcard/window_dump.xml"],
        check=True,
        capture_output=True,
        text=True,
    )
    return parse_uiautomator_dump(xml_result.stdout)


def find_send_button(ui_state) -> ButtonTarget:
    screen_width = ui_state.screen_width or 1080
    screen_height = ui_state.screen_height or 2400
    semantic_candidates: list[ButtonTarget] = []
    candidates: list[ButtonTarget] = []

    for element in ui_state.elements:
        if element.get("className") != "Button":
            continue

        bounds = element.get("bounds")
        if not bounds:
            continue

        left, top, right, bottom = parse_bounds(bounds)
        if left < int(screen_width * 0.75):
            continue
        if top < int(screen_height * 0.85):
            continue

        target = _target_from_element(element)
        if _element_matches_any_text(element, {"发送", "发送消息", "Send", "Send message"}):
            semantic_candidates.append(target)
            continue

        candidates.append(target)

    if semantic_candidates:
        return sorted(semantic_candidates, key=lambda item: (item.bottom, item.right))[-1]

    if not candidates:
        raise RuntimeError("Unable to locate the bottom-right send button")

    return sorted(candidates, key=lambda item: (item.bottom, item.right))[-1]


def contains_message(ui_state, message: str) -> bool:
    for element in ui_state.elements:
        if element.get("className") == "EditText":
            continue
        if message in _element_texts(element):
            return True
    return False


def contains_confirmation_controls(ui_state) -> bool:
    matched_labels = {
        text
        for element in ui_state.elements
        for text in _element_texts(element)
        if text in {"继续", "取消", "继续，以后不再确认"}
    }
    return {"继续", "取消"}.issubset(matched_labels)


def should_fallback_to_uiautomator(raw_state: dict) -> bool:
    a11y_tree = raw_state.get("a11y_tree")
    if not isinstance(a11y_tree, list) or not a11y_tree:
        return True

    phone_state = raw_state.get("phone_state")
    if not isinstance(phone_state, dict):
        return True

    return False


async def save_screenshot(driver: AndroidDriver, output_dir: Path, name: str) -> None:
    image_bytes = await driver.screenshot()
    (output_dir / f"{name}.png").write_bytes(image_bytes)


async def _get_state_snapshot(driver, serial: str):
    try:
        raw_state = await driver.get_ui_tree()
        if should_fallback_to_uiautomator(raw_state):
            raise RuntimeError(f"Portal returned empty or incompatible state: {raw_state}")

        from droidrun.tools.filters.concise_filter import ConciseFilter
        from droidrun.tools.formatters.indexed_formatter import IndexedFormatter
        from droidrun.tools.ui.state import UIState

        formatter = IndexedFormatter()
        tree_filter = ConciseFilter()
        filtered_tree = tree_filter.apply(raw_state["a11y_tree"])
        return UIState(
            elements=formatter.format(filtered_tree),
            phone_state=raw_state["phone_state"],
            device_context=raw_state["device_context"],
        )
    except Exception as error:
        print(f"Portal state unavailable, falling back to uiautomator dump: {error}")
        return _fetch_uiautomator_state(serial)


async def main() -> int:
    from droidrun.tools.driver.android import AndroidDriver

    serial = os.environ.get("ANDROID_SERIAL", "AUUNW22B08000071")
    package = os.environ.get("APP_PACKAGE", "com.example.ai_chat")
    activity = os.environ.get("APP_ACTIVITY", ".MainActivity")
    message = os.environ.get(
        "SMOKE_MESSAGE",
        f"droidrun driver smoke {datetime.now().strftime('%Y%m%d-%H%M%S')}",
    )
    expected_confirmation = os.environ.get("EXPECTED_CONFIRMATION_TEXT")

    output_dir = Path("build/droidrun/driver-smoke") / datetime.now().strftime(
        "%Y%m%d_%H%M%S"
    )
    output_dir.mkdir(parents=True, exist_ok=True)

    driver = AndroidDriver(serial=serial)
    await driver.connect()
    print(f"Connected to {serial}")

    start_result = await driver.start_app(package, activity)
    print(start_result)
    await asyncio.sleep(2)

    initial_state = await _get_state_snapshot(driver, serial)
    try:
        await save_screenshot(driver, output_dir, "before_send")
    except Exception as error:
        print(f"Skipping screenshot capture because Portal screenshot failed: {error}")

    current_package = (getattr(initial_state, "phone_state", {}) or {}).get("packageName")
    if current_package != package:
        print(f"App not foregrounded. Current package: {current_package}")
        return 2

    send_button = find_send_button(initial_state)
    input_target = find_chat_input_target(initial_state)

    print(
        f"Using send button index={send_button.index} at "
        f"({send_button.center_x}, {send_button.center_y})",
    )
    print(
        f"Using input index={input_target.index} at "
        f"({input_target.center_x}, {input_target.center_y}) with message: {message}",
    )

    message_visible = False

    for attempt in range(1, 4):
        await driver.tap(input_target.center_x, input_target.center_y)
        await asyncio.sleep(0.3)
        typed = await driver.input_text(message, clear=True)
        print(f"Attempt {attempt}: input_text returned {typed}")
        await asyncio.sleep(0.3)
        await driver.tap(send_button.center_x, send_button.center_y)
        await asyncio.sleep(1.5)

        current_state = await _get_state_snapshot(driver, serial)
        try:
            await save_screenshot(driver, output_dir, f"after_attempt_{attempt}")
        except Exception as error:
            print(
                "Skipping screenshot capture after send because Portal screenshot "
                f"failed: {error}",
            )

        if contains_message(current_state, message):
            message_visible = True
            if expected_confirmation and not contains_confirmation_controls(current_state):
                print(
                    "Message sent, but confirmation controls are not visible yet; "
                    "continuing to poll.",
                )
                await asyncio.sleep(1)
                continue

            print(f"Smoke test passed: found message '{message}'")
            if expected_confirmation:
                print(
                    "Smoke test passed: confirmation controls detected for "
                    f"'{expected_confirmation}'",
                )
            print(f"Artifacts saved to {output_dir}")
            return 0

    if not message_visible:
        print(f"Smoke test failed: message '{message}' was not found")
    else:
        print(
            f"Smoke test failed: message '{message}' was sent, but the expected "
            "confirmation controls never appeared",
        )
    if expected_confirmation:
        print(
            "Smoke test also failed to detect confirmation controls for "
            f"'{expected_confirmation}'",
        )
    print(f"Artifacts saved to {output_dir}")
    return 1


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
