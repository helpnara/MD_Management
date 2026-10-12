#!/usr/bin/env python3
"""`project.yml` 에 미리보기 영상용 UI 시험 대상과 스킴을 **CI 에서만** 덧붙인다 (`store-preview.yml`).

앱 빌드 · 테스트플라이트가 쓰는 `project.yml` 은 그대로 둔다 — 이 흐름 안에서만 고친 사본으로 프로젝트를 만든다.
"""
from pathlib import Path

p = Path("project.yml")
s = p.read_text(encoding="utf-8")
assert "StorePreviewUITests" not in s
s = s.rstrip("\n") + """

  StorePreviewUITests:
    type: bundle.ui-testing
    platform: iOS
    sources:
      - path: Tools/store/preview/StorePreviewUITests.swift
    dependencies:
      - target: Notebook
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.helpnara.markdown.storepreview
        TEST_TARGET_NAME: Notebook
        GENERATE_INFOPLIST_FILE: YES
        TARGETED_DEVICE_FAMILY: "1,2"

schemes:
  StorePreview:
    build:
      targets:
        Notebook: all
        StorePreviewUITests: [test]
    test:
      config: Debug
      targets:
        - StorePreviewUITests
"""
p.write_text(s + "\n", encoding="utf-8")
print("project.yml 에 StorePreviewUITests · StorePreview 스킴을 붙였다")
