import unittest
from types import SimpleNamespace

from scripts.android_droidrun_driver_smoke import (
    contains_message_in_input_field,
    contains_confirmation_controls,
    contains_message,
    find_chat_input_target,
    find_send_button,
    normalize_text_for_adb_input,
    parse_uiautomator_dump,
    should_fallback_to_uiautomator,
)


class AndroidDroidrunDriverSmokeTest(unittest.TestCase):
    def test_find_send_button_prefers_semantic_send_label(self):
        ui_state = SimpleNamespace(
            screen_width=1080,
            screen_height=2400,
            elements=[
                {
                    "index": 7,
                    "className": "Button",
                    "bounds": "843,2149,1027,2253",
                    "contentDescription": "发送",
                },
                {
                    "index": 2,
                    "className": "Button",
                    "bounds": "949,122,1088,260",
                    "contentDescription": "",
                },
            ],
        )

        target = find_send_button(ui_state)

        self.assertEqual(7, target.index)
        self.assertEqual(935, target.center_x)
        self.assertEqual(2201, target.center_y)

    def test_find_chat_input_target_prefers_semantic_chat_input(self):
        ui_state = SimpleNamespace(
            screen_width=1080,
            screen_height=2400,
            elements=[
                {
                    "index": 11,
                    "className": "EditText",
                    "bounds": "61,2201,819,2253",
                    "contentDescription": "聊天输入框",
                    "text": "空白",
                },
            ],
        )

        target = find_chat_input_target(ui_state)

        self.assertEqual(11, target.index)
        self.assertEqual(440, target.center_x)
        self.assertEqual(2227, target.center_y)

    def test_contains_confirmation_controls_detects_tool_confirmation(self):
        ui_state = SimpleNamespace(
            elements=[
                {"text": "继续", "className": "Button"},
                {"text": "取消", "className": "Button"},
                {"text": "继续，以后不再确认", "className": "Button"},
            ],
        )

        self.assertTrue(contains_confirmation_controls(ui_state))

    def test_parse_uiautomator_dump_extracts_semantic_elements(self):
        xml = """
        <hierarchy rotation="0">
          <node index="0" class="android.view.View" bounds="[0,2091][1088,2292]" content-desc="聊天输入区域&#10;Balanced · 可追溯输出">
            <node index="0" text="空白" class="android.widget.EditText" bounds="[61,2201][819,2253]" />
            <node index="1" class="android.widget.Button" bounds="[843,2149][1027,2253]" content-desc="发送" />
          </node>
        </hierarchy>
        """

        ui_state = parse_uiautomator_dump(xml)

        self.assertEqual(1088, ui_state.screen_width)
        self.assertEqual(2292, ui_state.screen_height)
        input_element = next(
            element for element in ui_state.elements if element["className"] == "EditText"
        )
        send_element = next(
            element
            for element in ui_state.elements
            if element["contentDescription"] == "发送"
        )
        self.assertEqual("空白", input_element["text"])
        self.assertEqual("Button", send_element["className"])

    def test_should_fallback_to_uiautomator_for_empty_tree(self):
        raw_state = {
            "a11y_tree": [],
            "phone_state": {"activityName": "", "keyboardVisible": False},
            "device_context": {},
        }

        self.assertTrue(should_fallback_to_uiautomator(raw_state))

    def test_contains_message_matches_content_description(self):
        ui_state = SimpleNamespace(
            elements=[
                {
                    "className": "View",
                    "text": "",
                    "contentDescription": "create a reminder for today at 8pm to submit weekly report",
                },
            ],
        )

        self.assertTrue(
            contains_message(
                ui_state,
                "create a reminder for today at 8pm to submit weekly report",
            )
        )

    def test_contains_message_matches_substring_inside_longer_accessibility_text(self):
        ui_state = SimpleNamespace(
            elements=[
                {
                    "className": "View",
                    "text": "",
                    "contentDescription": (
                        "droidrun driver smoke 20260414-020808"
                        "droidrun driver smoke 20260414-020948"
                    ),
                },
            ],
        )

        self.assertTrue(
            contains_message(ui_state, "droidrun driver smoke 20260414-020948")
        )

    def test_contains_message_ignores_text_still_inside_input_field(self):
        ui_state = SimpleNamespace(
            screen_height=2292,
            elements=[
                {
                    "className": "EditText",
                    "text": "create a reminder for today at 8pm to submit weekly report",
                    "contentDescription": "",
                    "bounds": "61,2051,819,2155",
                },
            ],
        )

        self.assertFalse(
            contains_message(
                ui_state,
                "create a reminder for today at 8pm to submit weekly report",
            )
        )

    def test_contains_message_in_input_field_detects_text_inside_edit_text(self):
        ui_state = SimpleNamespace(
            elements=[
                {
                    "className": "EditText",
                    "text": "android e2e reminder smoke",
                    "contentDescription": "",
                },
            ],
        )

        self.assertTrue(
            contains_message_in_input_field(ui_state, "android e2e reminder smoke")
        )

    def test_normalize_text_for_adb_input_rewrites_spaces_and_special_chars(self):
        normalized = normalize_text_for_adb_input(
            "remind me & summarize (today) 100%"
        )

        self.assertEqual(
            "remind%sme%s\\&%ssummarize%s\\(today\\)%s100\\%",
            normalized,
        )


if __name__ == "__main__":
    unittest.main()
