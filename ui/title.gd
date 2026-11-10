# タイトル画面。Phase 0 は日本語の題名と版だけを出す。
# 文言は core/strings.gd から、版は project.godot の application/config/version から読む(仕様書 §9.10)。
extends Control

const Strings := preload("res://core/strings.gd")

@onready var _title: Label = %TitleLabel
@onready var _product: Label = %ProductLabel
@onready var _version: Label = %VersionLabel


func _ready() -> void:
	_title.text = Strings.TITLE
	_product.text = Strings.PRODUCT
	_version.text = Strings.VERSION_FORMAT % ProjectSettings.get_setting("application/config/version")
