extends CanvasLayer

@onready var container: VBoxContainer = $VBoxContainer


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var cover := container.get_node("Cover") as TextureRect
	var artist := container.get_node("Artist") as Label
	var track := container.get_node("Track") as Label
	var year := container.get_node("Year") as Label
	var album := container.get_node("Album") as Label

	#Load a data and create a new AudioStreamMP3
	var file := FileAccess.get_file_as_bytes("/Volumes/Open/Music/people.mp3")
	var stream := AudioStreamMP3.new()
	stream.data = file

	#Create a new parser class and attach desired AudioStreamMP3
	var tagReader := MP3ID3Tag.new()
	tagReader.stream = stream

	#Extract only the information you need
	artist.text = tagReader.getArtist()
	track.text = tagReader.getTrackName()
	year.text = tagReader.getYear()
	album.text = tagReader.getAlbum()

	#Images are extracted as Image class
	var pic: Image = tagReader.getAttachedPicture()
	var imgTexture: ImageTexture = ImageTexture.create_from_image(pic)
	cover.texture = imgTexture

	#List all extracted frames
	tagReader.frames

	#get main ID3 heater info
	tagReader.header
