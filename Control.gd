extends Control

const MB_RAITO : float = 0.000001

export var archive_name = "GDApplibArchive2"

var base_url: String = "http://vps-cab32ee4.vps.ovh.ca:8081/api/v1"
var archive_path: String = "res"
var archive: String = "archive.tar.br"
var chunk_size: int = 1 * 1024 * 1024 # 1MB
var start_chunk = 0
var current_chunk: int = 0
var total_chunks: int = 0
var reminder: int = 0
var max_retries: int = 3
var jwt: String

var uploading: bool = false

var upload_state: int = -1
var download_state: int = -1
var hc = HashingContext.new()

signal authenticated()
signal app_created(app_id)
signal continue_upload(success)
signal continue_download(bytes)
signal upload_initialized()
signal archive_chunks(chunks)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
    pass

func start_downloading() -> void:
    var archive_id: String = "03fa0024-4c6d-426a-bbc5-6ba4fec94938"
    print("Getting information about archive ", archive_id)
    download_state = 0
    $Download.request(
        base_url + "/archives/" + archive_id + "/chunks",
        [],
        false,
        HTTPClient.METHOD_GET,
        ""
       )
    var archive_chunks: int = yield(self, "archive_chunks")
    print(archive_chunks, " chunks found!")
    
    print("started downloading '", archive, "' ...")
    download_state = 1
    var file: File = File.new()
    file.open("res/download/archive.tar.br", File.WRITE)
    for i in archive_chunks:
        print("downloading chunk %d" % i)
        $Download.request(
            base_url + "/archives/" + archive_id + "/chunks/%s" % i,
            [],
            false,
            HTTPClient.METHOD_GET,
            ""
        )
        var bytes: PoolByteArray = yield(self, "continue_download")
        file.store_buffer(bytes)
    print("download ended.")

func start_upload() -> void:
    print("Authenticating...")
    $Authentication.request(
        base_url + "/auth/login",
        ["Content-Type: application/json"],
        false,
        HTTPClient.METHOD_POST,
        JSON.print(
            {
                "email":"nicolo.santilio@outlook.com",
                "password":"fenixhub"
            }
        )
    )
    yield(self, "authenticated")
    print("Authenticated")
    
    print("Creating new app...")
    upload_state = 0
    $Upload.request(base_url + "/apps", ["Authorization: Bearer %s" % jwt, "Content-Type: application/json"], false, HTTPClient.METHOD_PUT, 
    JSON.print({ name = archive_name, developer = "fenixhub" })
    )
    var app_id: int = yield(self, "app_created")
    print("App created!")
    
    
    print("Initializing upload")
    upload_state = 1
    var file = File.new()
    var err = file.open(archive_path + "/" + archive, File.READ)
    if err != OK:
        printerr("Error opening file")
        return
    var file_len: int = file.get_len()
    var file_content = file.get_buffer(file_len)
    file.close()
    reminder = file_len % chunk_size
    total_chunks = (file_len / chunk_size) 
    total_chunks += int(reminder != 0)

    $Upload.request(base_url + "/archives/initialize", ["Authorization: Bearer %s" % jwt, "Content-Type: application/json"], false, HTTPClient.METHOD_POST, 
    JSON.print({ appId = app_id, archive = archive, "hash" : file.get_sha256(archive_path + "/" + archive), "size": file_len, "chunks":total_chunks, "version":"3" })
    )
    var archive_id: String = yield(self, "upload_initialized")
    print("Upload initialized")
    
    upload_state = 2
    print("Starting upload of ", archive)
    print("Starting upload of ", total_chunks, " chunks (", file_len * MB_RAITO, " MB)")
    print("Chunk size set to ", chunk_size * MB_RAITO, " MB (", chunk_size, " bytes)")
    for current_chunk in range(start_chunk, total_chunks):
        self.current_chunk = current_chunk
        if uploading == false:
            break
        var chunk_content: PoolByteArray = file_content.subarray(chunk_size * current_chunk, min(chunk_size * (current_chunk + 1) - 1, file_len-1))
        var payload = Marshalls.raw_to_base64(chunk_content)
        
        hc.start(HashingContext.HASH_SHA256)
        hc.update(chunk_content)
        var _hash: PoolByteArray = hc.finish()
        
        upload(archive_id, payload, chunk_content.size(), current_chunk, Marshalls.raw_to_base64(_hash).replacen("+","-").replacen("/","_"), current_chunk == (total_chunks - 1) )
        var success = yield(self, "continue_upload")
        if !success:
            break
#        if !success:
#            for retries in range(0, max_retries):
#                print("retrying download of chunk ", current_chunk, " (", retries, "/",max_retries,") ...")
#                upload(file_content, chunk_size * current_chunk, chunk_size * (current_chunk + 1) - 1, file_len, archive)
#                success = yield(self, "continue_upload")
#                if success:
#                    return
    uploading = false
    print("Upload completed.")
    

func upload(archive_id: String, payload: String, size: int, index: int, _hash: String, check_integrity: bool = false) -> void:
    var headers = [
            "Content-Type: message/byterange",
            "X-Chunk-Size: %s" % size,
            "X-Chunk-Index: %s" % index,
            "X-Chunk-Hash: %s" % _hash,
            "X-Check-Integrity: %s" % check_integrity,
            "Authorization: Bearer %s" % jwt
        ]
    print("uploading chunk ", index + 1, "/", total_chunks,
    " (", size * MB_RAITO, " MB)"
    )
    print("headers: ", headers)
    
    $Upload.request(
        base_url + "/archives/" + archive_id + "/chunks", 
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
        match download_state:
            0:
                emit_signal("archive_chunks", JSON.parse(body.get_string_from_utf8()).result.size())
            1:
                emit_signal("continue_download", Marshalls.base64_to_raw(body.get_string_from_utf8()))
                print("downloaded file.")
                print("")


func _on_Upload_request_completed(result: int, response_code: int, headers: PoolStringArray, body: PoolByteArray) -> void:
    print(response_code)
    match upload_state:
        0:
            var json = JSON.parse(body.get_string_from_utf8()).result
            print("APP CREATED: ", json)
            emit_signal("app_created", json.id)
        1:
            var json = JSON.parse(body.get_string_from_utf8()).result
            print("ARCHIVE ID: ", json.id)
            emit_signal("upload_initialized", json.id)
        2:
            print("chunk: ", current_chunk + 1, " --> ", response_code)
            print("")
            emit_signal("continue_upload", response_code == 200)


func _on_Button3_pressed() -> void:
    start_downloading()


func _on_Authentication_request_completed(result: int, response_code: int, headers: PoolStringArray, body: PoolByteArray) -> void:
    print(response_code)
    var json = JSON.parse(body.get_string_from_utf8()).result
    print(json.idToken)
    jwt = json.idToken
    emit_signal("authenticated")
