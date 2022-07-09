extends Control

const MB_RAITO = 0.000001

var base_url: String = "http://127.0.0.1:8080"
var package_endpoint: String = base_url+"/package/{package}"
var archive: String = "MinecraftInstaller.zip"
var chunk_size: int = 1 * 1024 * 1024 # 2MB
var start_chunk = 0
var current_chunk: int = 0
var total_chunks: int = 0
var reminder: int = 0
var max_retries: int = 3

var uploading: bool = false

signal continue_upload(success)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
    pass

func start_downloading() -> void:
    print("x ------")
    print("| started downloading")
    $Download.request(
        package_endpoint.format({package = archive}),
        [],
        false,
        HTTPClient.METHOD_GET,
        ""
    )

func start_upload() -> void:
    var content = File.new()
    content.open(archive, File.READ)
    var filelen: int = content.get_len()
    var filecont = content.get_buffer(filelen)
    content.close()
    reminder = filelen % chunk_size
    total_chunks = (filelen / chunk_size) 
    total_chunks += int(reminder != 0)
    print("Starting upload of ", total_chunks, " chunks (", filelen * MB_RAITO, " MB)")
    print("Chunk size set to ", chunk_size * MB_RAITO, " MB (", chunk_size, " bytes)")
    for current_chunk in range(start_chunk, total_chunks):
        self.current_chunk = current_chunk
        if uploading == false:
            return
        upload(filecont, chunk_size * current_chunk, chunk_size * (current_chunk + 1) - 1, filelen, archive)
        var success = yield(self, "continue_upload")
        
        if !success:
            for retries in range(0, max_retries):
                print("retrying download of chunk ", current_chunk, " (", retries, "/",max_retries,") ...")
                upload(filecont, chunk_size * current_chunk, chunk_size * (current_chunk + 1) - 1, filelen, archive)
                success = yield(self, "continue_upload")
                if success:
                    return
#    if current_chunk == total_chunks - 1 and reminder != 0 :
#        current_chunk += 1
#        upload(filecont, chunk_size * current_chunk, chunk_size * current_chunk + reminder - 1, filelen, archive)
#        yield(self, "continue_upload")
            
    uploading = false
    print("Upload completed.")
    

func upload(bytes: PoolByteArray, from : int, to : int, _len: int, archive: String) -> void:
    to = min(to, _len - 1)
    var payload = Marshalls.raw_to_base64(bytes.subarray(from, to))
    var headers = [
            "Content-Type: message/byterange",
            "Content-Range: bytes %s-%s/%s" % [from, to, _len],
            "X-Archive: %s" % archive,
        ]
    print("uploading chunk ", current_chunk + 1, "/", total_chunks,
    " (", (to - from) * MB_RAITO, " MB)"
    )
    print("headers: ", headers)
    
    $Upload.request(
        package_endpoint.format({package = "archive_1"}), 
        headers,
        false,
        HTTPClient.METHOD_PATCH,
        payload
    )
    yield(self, "continue_upload")

func _on_Button_pressed() -> void:
    uploading = true
    start_upload()


func _on_Button2_pressed() -> void:
    uploading = false
    start_chunk = current_chunk


func _on_Download_request_completed(result: int, response_code: int, headers: PoolStringArray, body: PoolByteArray) -> void:
    print("downloading response --> ", response_code)
    if response_code == 200:
        var file = File.new()
        file.open("res://downloaded.zip", File.WRITE)
        file.store_buffer(Marshalls.base64_to_raw(body.get_string_from_utf8()))
        print("downloaded file.")
        print()


func _on_Upload_request_completed(result: int, response_code: int, headers: PoolStringArray, body: PoolByteArray) -> void:
        print("chunk: ", current_chunk + 1, " --> ", response_code)
        print("")
        emit_signal("continue_upload", response_code == 200)


func _on_Button3_pressed() -> void:
    start_downloading()
