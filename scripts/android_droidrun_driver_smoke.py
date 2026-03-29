#!/usr/bin/env python3

import asyncio
import os
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

from droidrun.tools.driver.android import AndroidDriver
from droidrun.tools.filters.concise_filter import ConciseFilter
from droidrun.tools.formatters.indexed_formatter import IndexedFormatter
from droidrun.tools.ui.provider import AndroidStateProvider


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


def parse_bounds(bounds: str) -> tuple[int, int, int, int]:
    left, top, right, bottom = (int(part) for part in bounds.split(","))
    return left, top, right, bottom


def find_send_button(ui_state) -> ButtonTarget:
    screen_width = ui_state.screen_width or 1080
    screen_height = ui_state.screen_height or 2400
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

        candidates.append(
            ButtonTarget(
              index=element["index"],
              left=left,
              top=top,
              right=right,
              bottom=bottom,
            ),
        )

    if not candidates:
        raise RuntimeError("Unable to locate the bottom-right send button")

    return sorted(candidates, key=lambda item: (item.bottom, item.right))[-1]


def contains_message(ui_state, message: str) -> bool:
    return any(element.get("text") == message for element in ui_state.elements)


async def save_screenshot(driver: AndroidDriver, output_dir: Path, name: str) -> None:
    image_bytes = await driver.screenshot()
    (output_dir / f"{name}.png").write_bytes(image_bytes)


async def main() -> int:
    serial = os.environ.get("ANDROID_SERIAL", "AUUNW22B08000071")
    package = os.environ.get("APP_PACKAGE", "com.example.ai_chat")
    activity = os.environ.get("APP_ACTIVITY", ".MainActivity")
    message = os.environ.get(
        "SMOKE_MESSAGE",
        f"droidrun driver smoke {datetime.now().strftime('%Y%m%d-%H%M%S')}",
    )

    output_dir = Path("build/droidrun/driver-smoke") / datetime.now().strftime(
        "%Y%m%d_%H%M%S"
    )
    output_dir.mkdir(parents=True, exist_ok=True)

    driver = AndroidDriver(serial=serial)
    provider = AndroidStateProvider(
        driver=driver,
        tree_filter=ConciseFilter(),
        tree_formatter=IndexedFormatter(),
    )

    await driver.connect()
    print(f"Connected to {serial}")

    start_result = await driver.start_app(package, activity)
    print(start_result)
    await asyncio.sleep(2)

    initial_state = await provider.get_state()
    await save_screenshot(driver, output_dir, "before_send")

    current_package = initial_state.phone_state.get("packageName")
    if current_package != package:
        print(f"App not foregrounded. Current package: {current_package}")
        return 2

    send_button = find_send_button(initial_state)
    input_x = max(80, send_button.left - 250)
    input_y = send_button.center_y

    print(
        f"Using send button index={send_button.index} at "
        f"({send_button.center_x}, {send_button.center_y})",
    )
    print(f"Typing at ({input_x}, {input_y}) with message: {message}")

    for attempt in range(1, 4):
        await driver.tap(input_x, input_y)
        await asyncio.sleep(0.3)
        typed = await driver.input_text(message, clear=True)
        print(f"Attempt {attempt}: input_text returned {typed}")
        await asyncio.sleep(0.3)
        await driver.tap(send_button.center_x, send_button.center_y)
        await asyncio.sleep(1.5)

        current_state = await provider.get_state()
        await save_screenshot(driver, output_dir, f"after_attempt_{attempt}")

        if contains_message(current_state, message):
            print(f"Smoke test passed: found message '{message}'")
            print(f"Artifacts saved to {output_dir}")
            return 0

    print(f"Smoke test failed: message '{message}' was not found")
    print(f"Artifacts saved to {output_dir}")
    return 1


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
