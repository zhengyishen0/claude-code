#!/usr/bin/env python3
"""Exhaustive tests for hint_keywords.py

Run: python3 test_hint_keywords.py
"""

import sys
from hint_keywords import extract_keywords, has_cjk, extract_english_keywords, extract_chinese_keywords, JIEBA_AVAILABLE

# Test result tracking
passed = 0
failed = 0

def test(name, text, expected_contains=None, expected_not_contains=None, min_keywords=0, max_keywords=None):
    """Run a single test case."""
    global passed, failed

    result = extract_keywords(text)

    errors = []

    # Check minimum keywords
    if len(result) < min_keywords:
        errors.append(f"Expected at least {min_keywords} keywords, got {len(result)}")

    # Check maximum keywords
    if max_keywords is not None and len(result) > max_keywords:
        errors.append(f"Expected at most {max_keywords} keywords, got {len(result)}")

    # Check expected keywords are present
    if expected_contains:
        for kw in expected_contains:
            if kw not in result:
                errors.append(f"Expected '{kw}' in results")

    # Check excluded keywords are absent
    if expected_not_contains:
        for kw in expected_not_contains:
            if kw in result:
                errors.append(f"Did not expect '{kw}' in results")

    if errors:
        failed += 1
        print(f"FAIL: {name}")
        print(f"  Input: {text}")
        print(f"  Output: {result}")
        for e in errors:
            print(f"  Error: {e}")
    else:
        passed += 1
        print(f"PASS: {name} -> {result}")


def test_has_cjk():
    """Test CJK detection."""
    global passed, failed

    cases = [
        ("hello", False),
        ("你好", True),
        ("hello 你好", True),
        ("こんにちは", True),
        ("안녕하세요", False),  # Korean - not in our CJK range for now
        ("123", False),
        ("", False),
        ("hello世界world", True),
    ]

    for text, expected in cases:
        result = has_cjk(text)
        if result == expected:
            passed += 1
            print(f"PASS: has_cjk('{text}') = {result}")
        else:
            failed += 1
            print(f"FAIL: has_cjk('{text}') expected {expected}, got {result}")


print("=" * 60)
print("Testing has_cjk()")
print("=" * 60)
test_has_cjk()

print("\n" + "=" * 60)
print("Testing English keyword extraction")
print("=" * 60)

# Basic English tests
test("simple_english",
     "help me debug the browser automation",
     expected_contains=["browser", "automation"],
     expected_not_contains=["help", "me", "the", "debug"])  # debug is a stopword

test("english_with_stopwords",
     "I want to find the error in my code",
     expected_contains=["error", "code"],
     expected_not_contains=["i", "want", "to", "find", "the", "in", "my"])

test("technical_terms",
     "fix the OAuth authentication flow",
     expected_contains=["oauth", "authentication", "flow"],
     expected_not_contains=["fix", "the"])

test("mixed_case",
     "Debug the API endpoint for UserAuthentication",
     expected_contains=["api", "endpoint", "userauthentication"],
     expected_not_contains=["debug", "the", "for"])

test("short_words_filtered",
     "I am at my PC to do it",
     expected_not_contains=["am", "at", "my", "pc", "to", "do", "it"],
     max_keywords=0)  # All should be filtered (short or stopwords)

test("numbers_ignored",
     "check error 404 in file123",
     expected_contains=["error"],
     expected_not_contains=["404", "123", "check"])  # check is a stopword

test("punctuation_handling",
     "what's the bug in user.authentication?",
     expected_contains=["bug", "user", "authentication"],
     expected_not_contains=["what", "the", "in", "s"])

test("hyphenated_words",
     "fix the re-authentication flow",
     expected_contains=["authentication", "flow"],
     expected_not_contains=["fix", "the"])

test("question_format",
     "how do I configure the browser settings?",
     expected_contains=["configure", "browser", "settings"],
     expected_not_contains=["how", "the"])

test("command_style",
     "show me the feishu approval records",
     expected_contains=["feishu", "approval", "records"],
     expected_not_contains=["show", "the"])

print("\n" + "=" * 60)
print("Testing Chinese keyword extraction")
print("=" * 60)

if JIEBA_AVAILABLE:
    print("(Using jieba for segmentation)")
else:
    print("(Using bigram fallback - jieba not available)")

test("simple_chinese",
     "帮我看看飞书审批的问题",
     expected_contains=["飞书", "审批", "问题"],
     expected_not_contains=["帮我", "看看", "的"])

test("chinese_technical",
     "浏览器自动化有个错误",
     expected_contains=["浏览器", "自动化", "错误"],
     expected_not_contains=["有个"])

test("chinese_question",
     "怎么配置日历同步功能",
     expected_contains=["配置", "日历", "功能"],
     expected_not_contains=["怎么"])

test("chinese_stopwords",
     "我想要知道这个API的用法",
     expected_contains=["api", "用法"],
     expected_not_contains=["想要", "知道"])

test("chinese_with_punctuation",
     "飞书机器人怎么发消息？",
     expected_contains=["飞书", "机器人"],
     expected_not_contains=["怎么"])

print("\n" + "=" * 60)
print("Testing mixed Chinese/English")
print("=" * 60)

test("mixed_simple",
     "帮我调试 browser 的问题",
     expected_contains=["browser", "调试", "问题"],
     expected_not_contains=["帮", "我", "的"])

test("mixed_technical",
     "feishu API 调用失败了",
     expected_contains=["feishu", "api", "调用", "失败"],
     expected_not_contains=["了"])

test("mixed_question",
     "how to 配置 OAuth 认证",
     expected_contains=["oauth", "配置", "认证"],
     expected_not_contains=["how", "to"])

test("mixed_complex",
     "我想用 Claude 来 automate 飞书审批流程",
     expected_contains=["claude", "automate", "飞书"],
     expected_not_contains=["想"])

test("english_in_chinese_context",
     "这个bug是在authentication模块里",
     expected_contains=["bug", "authentication", "模块"],
     expected_not_contains=["这个", "是", "在", "里"])

print("\n" + "=" * 60)
print("Testing more mixed Chinese/English cases")
print("=" * 60)

# Technical terms with Chinese context
test("api_in_chinese",
     "这个API返回的数据格式不对",
     expected_contains=["api", "返回", "数据格式"],  # '数据格式' is a compound word
     expected_not_contains=["这个", "的", "不对"])

test("code_terms_mixed",
     "browser里面的click方法报错",
     expected_contains=["browser", "click", "方法", "报错"],
     expected_not_contains=["里面", "的"])

test("product_names_mixed",
     "用Claude来自动化飞书的工作流",
     expected_contains=["claude", "自动化", "飞书", "工作"],
     expected_not_contains=["用", "来", "的"])

test("error_message_mixed",
     "TypeError: 无法读取undefined的属性",
     expected_contains=["typeerror", "读取", "undefined", "属性"],
     expected_not_contains=["无法", "的"])

test("command_mixed",
     "执行npm install之后还是报错",
     expected_contains=["npm", "install", "报错"],
     expected_not_contains=["执行", "之后", "还是"])

test("path_mixed",
     "在src/components目录下找不到文件",
     expected_contains=["src", "components", "目录", "文件"],
     expected_not_contains=["在", "下"])

test("config_mixed",
     "OAuth配置的client_id好像不对",
     expected_contains=["oauth", "配置"],
     expected_not_contains=["的", "好像", "不对"])

test("service_mixed",
     "Google Calendar同步到飞书日历失败",
     expected_contains=["google", "calendar", "飞书", "日历", "失败", "同步"],  # 同步 is meaningful
     expected_not_contains=["到"])

test("debug_mixed",
     "console.log输出的结果和预期不一样",
     expected_contains=["console", "log", "输出", "结果", "预期"],
     expected_not_contains=["的", "和"])

test("feature_mixed",
     "能不能给bot添加一个webhook功能",
     expected_contains=["bot", "webhook", "功能"],
     expected_not_contains=["能不能", "给", "添加", "一个"])

# Real conversation patterns
test("recall_mixed",
     "之前讨论的browser automation方案是什么",
     expected_contains=["browser", "automation", "方案"],
     expected_not_contains=["之前", "讨论", "的", "是", "什么"])

test("followup_mixed",
     "上次说的feishu API问题解决了吗",
     expected_contains=["feishu", "api", "问题", "解决"],
     expected_not_contains=["上次", "说", "的", "了", "吗"])

test("context_switch",
     "先不管OAuth的事，帮我看看日历sync",
     expected_contains=["oauth", "日历", "sync"],
     expected_not_contains=["先", "不管", "的", "事", "帮我", "看看"])

# Edge cases for mixed content
test("english_in_quotes_zh",
     '他说"browser automation"很好用',
     expected_contains=["browser", "automation"],
     expected_not_contains=["他", "说", "很", "好用"])

test("chinese_brand_english_tech",
     "飞书的GraphQL API怎么调用",
     expected_contains=["飞书", "graphql", "api", "调用"],
     expected_not_contains=["的", "怎么"])

test("mixed_acronyms",
     "用JWT做OAuth认证的SSO方案",
     expected_contains=["jwt", "oauth", "认证", "sso", "方案"],
     expected_not_contains=["用", "做", "的"])

print("\n" + "=" * 60)
print("Testing edge cases")
print("=" * 60)

test("empty_string",
     "",
     max_keywords=0)

test("only_stopwords_en",
     "I want to do this thing",
     max_keywords=2)  # Most should be filtered

test("only_stopwords_zh",
     "我想要这个",
     max_keywords=0)  # All should be filtered

test("only_punctuation",
     "!@#$%^&*()",
     max_keywords=0)

test("only_numbers",
     "123 456 789",
     max_keywords=0)

test("single_word",
     "authentication",
     expected_contains=["authentication"],
     min_keywords=1)

test("single_chinese_word",
     "认证",
     expected_contains=["认证"],
     min_keywords=1)

test("max_keywords_limit",
     "one two three four five six seven eight nine ten eleven twelve",
     max_keywords=6)

test("whitespace_handling",
     "  feishu   the    browser   ",
     expected_contains=["feishu", "browser"],
     expected_not_contains=["the"])

test("newlines",
     "feishu\nthe\nbrowser\nautomation",
     expected_contains=["feishu", "browser", "automation"],
     expected_not_contains=["the"])

test("tabs",
     "feishu\tthe\tbrowser",
     expected_contains=["feishu", "browser"],
     expected_not_contains=["the"])

print("\n" + "=" * 60)
print("Testing real-world user messages")
print("=" * 60)

test("continue_conversation",
     "continue where we left off yesterday",
     expected_contains=["yesterday"],  # Most words are stopwords
     expected_not_contains=["where", "off", "continue", "left"])

test("reference_past",
     "remember that issue with feishu bot last week",
     expected_contains=["issue", "feishu", "bot", "week"],
     expected_not_contains=["remember", "that", "with", "last"])

test("debug_request",
     "can you help me debug the approval workflow error",
     expected_contains=["approval", "workflow", "error"],
     expected_not_contains=["can", "help", "debug", "the"])

test("feature_request",
     "add support for google calendar sync",
     expected_contains=["support", "google", "calendar", "sync"],
     expected_not_contains=["add", "for"])

test("bug_report",
     "the browser automation is broken in headless mode",
     expected_contains=["browser", "automation", "broken", "headless", "mode"],
     expected_not_contains=["the", "is", "in"])

test("chinese_debug",
     "飞书审批流程报错了，能帮我看看吗",
     expected_contains=["飞书", "报错"],  # '审批流程' is a compound word
     expected_not_contains=["看看"])

test("chinese_feature",
     "我想给日历添加一个提醒功能",
     expected_contains=["日历", "提醒", "功能"],
     expected_not_contains=["想"])

test("mixed_real",
     "feishu bot 发送消息失败，看看是不是 API key 的问题",
     expected_contains=["feishu", "bot", "api"],  # 'key' may be cut off by max_keywords=6
     expected_not_contains=["看看", "是不是"])

test("code_reference",
     "check the implementation in browser/cli.js",
     expected_contains=["implementation", "browser", "cli"],
     expected_not_contains=["check", "the", "in"])

test("error_message",
     "getting TypeError: Cannot read property 'click' of undefined",
     expected_contains=["typeerror", "cannot", "property", "click", "undefined"],
     expected_not_contains=["getting"])

print("\n" + "=" * 60)
print("Testing keyword ordering (first = most important)")
print("=" * 60)

def test_order(name, text, expected_first):
    """Test that expected keyword appears first."""
    global passed, failed
    result = extract_keywords(text)

    if result and result[0] == expected_first:
        passed += 1
        print(f"PASS: {name} -> first keyword is '{result[0]}'")
    else:
        failed += 1
        first = result[0] if result else "(empty)"
        print(f"FAIL: {name} -> expected first '{expected_first}', got '{first}'")
        print(f"  Full result: {result}")

# Keywords should appear in order of appearance in text
test_order("order_preserved",
           "feishu approval browser automation",
           "feishu")

test_order("order_after_stopwords",
           "please help me with feishu approval",
           "feishu")

test_order("order_chinese",
           "飞书审批流程有问题",
           "飞书")

print("\n" + "=" * 60)
print(f"SUMMARY: {passed} passed, {failed} failed")
print("=" * 60)

sys.exit(0 if failed == 0 else 1)
