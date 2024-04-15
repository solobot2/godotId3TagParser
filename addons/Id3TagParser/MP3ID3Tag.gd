class_name MP3ID3Tag
const TAG_HEADER_LENGTH: int = 10

const FRAME_HEADER_LENGTH: int = 10

const STRING_TERMINATOR = 0x00
const STRING_TERMINATOR_UTF = [0x00, 0x00]

var _ID3Header: ID3MainHeader
var _frames: Dictionary = {}
var _stream: AudioStreamMP3

var bytesShift: int


class ID3MainHeader:
	var isId3: bool
	var id3Ver: String
	var unsync: bool
	var compress: bool
	var size: int


class StreamBufferPeerStrings:
	extends StreamPeerBuffer
	const STRING_TERMINATOR = [0x00]
	const STRING_TERMINATOR_UTF = [0x00, 0x00]

	func get_terminated_string(isUnicode: bool = false) -> PackedByteArray:
		var tmt := STRING_TERMINATOR_UTF if isUnicode else STRING_TERMINATOR
		var isTerminated: bool = false
		var stringBytes: PackedByteArray = []
		var tBuff: Array[int] = []
		while !isTerminated:
			var byte: int = get_u8()
			stringBytes.append(byte)
			tBuff.append(byte)
			if tBuff.size() > tmt.size():
				tBuff.pop_front()
			if tBuff == tmt:
				isTerminated = true

		return stringBytes


var stream: AudioStreamMP3:
	set(stream):
		_clear()
		_stream = stream
	get:
		return _stream

var header: ID3MainHeader:
	get:
		assert(_stream is AudioStreamMP3)
		if !_ID3Header:
			_ID3Header = _decode_head()
		return _ID3Header

var frames: Dictionary:
	get:
		if !_frames:
			_frames = _decode_frame_heads()
		return _frames


func _decode_frame_heads() -> Dictionary:
	if !header.isId3:
		return {}

	var frameStart: int = TAG_HEADER_LENGTH

	var fms: Dictionary = {}

	while frameStart < _ID3Header.size:
		var frameLength: int = 0
		var frameHeaderBytes := _stream.data.slice(frameStart, frameStart + FRAME_HEADER_LENGTH)
		var frameId: StringName = (
			char(frameHeaderBytes[0])
			+ char(frameHeaderBytes[1])
			+ char(frameHeaderBytes[2])
			+ char(frameHeaderBytes[3])
		)
		frameLength = (
			frameHeaderBytes[4] << (bytesShift * 3)
			| frameHeaderBytes[5] << (bytesShift * 2)
			| frameHeaderBytes[6] << bytesShift
			| frameHeaderBytes[7]
		)
		if frameLength > 0:
			fms[frameId] = [frameStart, frameLength]
		frameStart += (FRAME_HEADER_LENGTH + frameLength)
	return fms


func _clear() -> void:
	_stream = null
	_ID3Header = null
	_frames = {}


func _decode_head() -> ID3MainHeader:
	var id3: String = ""
	var verH: int
	var verL: int
	var flags: int
	var size: int
	var isHeaderValid: bool = false

	var headerBytes := _stream.data.slice(0, TAG_HEADER_LENGTH)

	for i in headerBytes.size():
		var cv: int = headerBytes[i]
		match i:
			0, 1, 2:
				id3 += char(cv)
			3:
				verH = cv
			4:
				verL = cv
			5:
				flags = cv
			_:
				size = ((size << 7) | cv)

	isHeaderValid = (id3 == &"ID3" and verH < 0xFF and verL < 0xFF and size <= 0x1FFFFFFF)

	var headerObj := ID3MainHeader.new()

	if isHeaderValid:
		headerObj.isId3 = true
		headerObj.id3Ver = str(verH) + "." + str(verL)
		headerObj.unsync = flags & 0b10000000
		headerObj.compress = flags & 0b01000000
		headerObj.size = size

	bytesShift = 7 if headerObj.unsync else 8
	return headerObj


func getFrameData(frameName: StringName) -> Variant:
	if !frames.has(frameName):
		return null
	match Array(frameName.split()):
		["T", ..]:
			return _getFrameDataString(frameName)
		["C", "O", "M", "M"]:
			return _getFrameCommentDict(frameName)
		["A", "P", "I", "C"]:
			return _getFrameImage(frameName)

		_:
			return null


func _getFrameBytes(frameName: StringName) -> PackedByteArray:
	var start: int = frames[frameName][0] + FRAME_HEADER_LENGTH
	var end: int = start + frames[frameName][1]
	return stream.data.slice(start, end)


func _prepareByteTextToDecode(byteText: PackedByteArray) -> Array:
	var isUnicode: bool = byteText[0] > 0
	return [byteText.slice(1), isUnicode]


func _getFrameDataString(frameName: StringName) -> String:
	return _decodeByteText.callv(_prepareByteTextToDecode(_getFrameBytes(frameName)))


func _decodeByteText(text: PackedByteArray, isUnicode: bool) -> String:
	var decoded: String
	if isUnicode:
		match Array(text.slice(0, 4)):
			[0xFF, 0xFE, 0x0, 0x0], [0x0, 0x0, 0xFE, 0xFF]:
				decoded = text.get_string_from_utf32()
			[0xFF, 0xFE, ..], [0xFE, 0xFF, ..]:
				decoded = text.get_string_from_utf16()
			_:
				decoded = text.get_string_from_utf8()
	else:
		decoded = text.get_string_from_ascii()

	return decoded


func _getFrameCommentDict(frameName: StringName) -> Dictionary:
	var bytesText := _getFrameBytes(frameName)
	var preparedText := _prepareByteTextToDecode(bytesText)
	bytesText = preparedText[0] as PackedByteArray
	var lang := bytesText.slice(0, 3).get_string_from_ascii()

	var comment := bytesText.slice(3)
	var shortContEnd := comment.find(0x00)
	var longContStart := comment.rfind(0x00)
	var shortContent: String = ""
	var longContent: String = ""

	if shortContEnd > -1:
		shortContent = _decodeByteText(comment.slice(0, shortContEnd), preparedText[1])
	else:
		shortContent = _decodeByteText(comment.slice(0), preparedText[1])

	if longContStart > -1:
		longContent = _decodeByteText(comment.slice(longContStart + 1), preparedText[1])
	return {"lang": lang, "shortContent": shortContent, "longContent": longContent}


func _getFrameImage(frameName: StringName) -> Dictionary:
	var buff := StreamBufferPeerStrings.new()
	buff.data_array = _getFrameBytes(frameName)

	var isUnicode: bool = buff.get_u8()

	var mimeType := _decodeByteText(buff.get_terminated_string(isUnicode), isUnicode)
	var pType: int = buff.get_u8()
	var pDescr := _decodeByteText(buff.get_terminated_string(isUnicode), isUnicode)

	return {
		"mimeType": mimeType,
		"pictureType": pType,
		"description": pDescr,
		"pictureBytes": buff.data_array.slice(buff.get_position())
	}


func getArtist() -> String:
	var data: String
	for i in 4:
		data = _ensureString("TPE" + str(i + 1))
		if data:
			return data
	return ""


func getTrackName() -> String:
	return _ensureString("TIT2")


func getAlbum() -> String:
	return _ensureString("TALB")


func getYear() -> String:
	return _ensureString("TYER")


func getKey() -> String:
	return _ensureString("TKEY")


func getAttachedPicture() -> Image:
	var pDict: Dictionary = _ensureDict("APIC")
	var image := Image.new()
	var err: int
	match pDict.get("mimeType"):
		"image/jpeg", "image/jpg":
			err = image.load_jpg_from_buffer(pDict.pictureBytes)
		"image/png":
			err = image.load_png_from_buffer(pDict.pictureBytes)

	if err != OK:
		return null
	return image


func _ensureString(frameName: StringName) -> String:
	var data: Variant = getFrameData(frameName)
	return data if data is String else ""


func _ensureDict(frameName: StringName) -> Dictionary:
	var data: Variant = getFrameData(frameName)
	return data if data is Dictionary else {}
