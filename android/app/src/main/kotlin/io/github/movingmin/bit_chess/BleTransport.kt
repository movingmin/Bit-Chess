package io.github.movingmin.bit_chess

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

/**
 * BLE 1:1 연결 (ADR-001). 호스트 = 광고 + GATT 서버, 게스트 = 스캔 + GATT 클라이언트.
 * 바이트 조각만 주고받는다. 쪼개기·합치기와 메시지 형식은 Dart(lib/ble)가 맡는다.
 * 모든 BLE 콜백은 메인 스레드로 넘겨 처리한다(상태 변수 경합 방지).
 */
@SuppressLint("MissingPermission") // 호출 전에 Dart가 ensurePermissions로 확인한다
class BleTransport(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        val SERVICE: UUID = UUID.fromString("6b1f0001-6a52-4c8e-9a3e-2f2b3c4d5e60")
        val RX: UUID = UUID.fromString("6b1f0002-6a52-4c8e-9a3e-2f2b3c4d5e60") // 게스트→호스트 write
        val TX: UUID = UUID.fromString("6b1f0003-6a52-4c8e-9a3e-2f2b3c4d5e60") // 호스트→게스트 notify
        val CCCD: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
        const val PERM_REQ = 4201
    }

    private val main = Handler(Looper.getMainLooper())
    private val manager = activity.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    private val adapter: BluetoothAdapter? get() = manager.adapter
    private var sink: EventChannel.EventSink? = null
    private var permResult: MethodChannel.Result? = null

    // 호스트
    private var server: BluetoothGattServer? = null
    private var txChar: BluetoothGattCharacteristic? = null
    private var peer: BluetoothDevice? = null // 연결된 게스트(1개만)
    private var advData: Pair<AdvertiseData, AdvertiseData>? = null
    private var advertising = false

    // 게스트
    private var gatt: BluetoothGatt? = null
    private var rxChar: BluetoothGattCharacteristic? = null
    private var scanning = false

    private var mtu = 23
    private val queue = ArrayDeque<ByteArray>()
    private var busy = false // 쓰기/알림은 한 번에 하나

    fun dispose() {
        stopAll()
        activity.unregisterReceiver(stateReceiver)
    }

    private fun emit(vararg kv: Pair<String, Any?>) { main.post { sink?.success(mapOf(*kv)) } }
    private fun log(msg: String) = emit("type" to "log", "msg" to msg)

    private val stateReceiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context, i: Intent) {
            val s = i.getIntExtra(BluetoothAdapter.EXTRA_STATE, -1)
            if (s != BluetoothAdapter.STATE_ON && s != BluetoothAdapter.STATE_OFF) return
            if (s == BluetoothAdapter.STATE_OFF) main.post { stopAll() }
            emit("type" to "bluetooth", "on" to (s == BluetoothAdapter.STATE_ON))
        }
    }

    init {
        MethodChannel(messenger, "bitchess/ble").setMethodCallHandler(this)
        EventChannel(messenger, "bitchess/ble/events").setStreamHandler(this)
        activity.registerReceiver(stateReceiver, IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED))
    }

    override fun onListen(args: Any?, events: EventChannel.EventSink) { sink = events }
    override fun onCancel(args: Any?) { sink = null }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "bluetoothOn" -> result.success(adapter?.isEnabled == true)
                "ensurePermissions" -> ensurePermissions(result)
                "hasPermissions" -> result.success(needed().all { activity.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED })
                // 이미 한 번 물어본 뒤에만 의미 있음: 거부 상태인데 "설명 필요"가 false면 Android가 창을 더 안 띄운다.
                "permanentlyDenied" -> result.success(
                    needed().any { activity.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED } &&
                        needed().none { activity.shouldShowRequestPermissionRationale(it) },
                )
                "openAppSettings" -> {
                    activity.startActivity(
                        Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS, android.net.Uri.fromParts("package", activity.packageName, null)),
                    )
                    result.success(null)
                }
                "startHost" -> { startHost(call.argument<ByteArray>("roomId")!!, call.argument<String>("name")!!); result.success(null) }
                "startScan" -> { startScan(); result.success(null) }
                "stopScan" -> { stopScan(); result.success(null) }
                "connect" -> { connect(call.arguments as String); result.success(null) }
                "send" -> { enqueue(call.arguments as ByteArray); result.success(null) }
                "disconnect" -> { disconnect(); result.success(null) }
                "stop" -> { stopAll(); result.success(null) }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("ble", e.message ?: e.javaClass.simpleName, null)
        }
    }

    // ---- 권한 ----

    private fun needed(): Array<String> = if (Build.VERSION.SDK_INT >= 31) {
        arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_ADVERTISE)
    } else {
        arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
    }

    private fun ensurePermissions(result: MethodChannel.Result) {
        val missing = needed().filter { activity.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isEmpty()) return result.success(true)
        permResult = result
        activity.requestPermissions(missing.toTypedArray(), PERM_REQ)
    }

    fun onPermissionResult(code: Int, grants: IntArray) {
        if (code != PERM_REQ) return
        permResult?.success(grants.isNotEmpty() && grants.all { it == PackageManager.PERMISSION_GRANTED })
        permResult = null
    }

    // ---- 호스트 ----

    private fun startHost(roomId: ByteArray, name: String) {
        stopAll()
        val a = adapter ?: throw IllegalStateException("블루투스 없음")
        val tx = BluetoothGattCharacteristic(TX, BluetoothGattCharacteristic.PROPERTY_NOTIFY, 0).apply {
            addDescriptor(BluetoothGattDescriptor(CCCD, BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE))
        }
        val rx = BluetoothGattCharacteristic(RX, BluetoothGattCharacteristic.PROPERTY_WRITE, BluetoothGattCharacteristic.PERMISSION_WRITE)
        val service = BluetoothGattService(SERVICE, BluetoothGattService.SERVICE_TYPE_PRIMARY).apply {
            addCharacteristic(rx); addCharacteristic(tx)
        }
        txChar = tx
        server = manager.openGattServer(activity, serverCallback)?.apply { addService(service) }
            ?: throw IllegalStateException("GATT 서버를 열 수 없음")
        // 광고 31바이트 제한: 본 광고 = 서비스 UUID, 스캔 응답 = 방 ID 4바이트 + 이름 앞부분.
        val nameBytes = name.toByteArray(Charsets.UTF_8).let { b ->
            var n = minOf(b.size, 9)
            while (n > 0 && n < b.size && (b[n].toInt() and 0xC0) == 0x80) n-- // UTF-8 글자 중간에서 자르지 않음
            b.copyOf(n)
        }
        val data = AdvertiseData.Builder().addServiceUuid(ParcelUuid(SERVICE)).setIncludeDeviceName(false).build()
        val resp = AdvertiseData.Builder().addServiceData(ParcelUuid(SERVICE), roomId + nameBytes).setIncludeDeviceName(false).build()
        advData = data to resp
        if (a.bluetoothLeAdvertiser == null) throw IllegalStateException("이 기기는 BLE 광고를 지원하지 않음")
        advertise()
        log("방 열림: GATT 서버·광고 시작")
    }

    private fun advertise() {
        val (data, resp) = advData ?: return
        if (advertising) return
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
            .setConnectable(true).build()
        adapter?.bluetoothLeAdvertiser?.startAdvertising(settings, data, resp, advCallback)
        advertising = true
    }

    private fun stopAdvertise() {
        if (!advertising) return
        adapter?.bluetoothLeAdvertiser?.stopAdvertising(advCallback)
        advertising = false
    }

    private val advCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(s: AdvertiseSettings) = log("광고 중")
        override fun onStartFailure(code: Int) {
            main.post { advertising = false }
            emit("type" to "error", "msg" to "광고 실패 (코드 $code)")
        }
    }

    private val serverCallback = object : BluetoothGattServerCallback() {
        override fun onConnectionStateChange(d: BluetoothDevice, status: Int, state: Int) = main.post {
            if (state == BluetoothProfile.STATE_CONNECTED) {
                if (peer != null && peer?.address != d.address) {
                    server?.cancelConnection(d) // 연결은 1개만
                    log("두 번째 연결 시도를 끊음")
                    return@post
                }
                peer = d
                mtu = 23
                stopAdvertise()
                log("게스트 연결됨(구독 대기)")
            } else if (state == BluetoothProfile.STATE_DISCONNECTED && peer?.address == d.address) {
                peer = null
                resetQueue()
                emit("type" to "disconnected", "status" to status)
                advertise() // 다시 받을 수 있게
            }
        }.let { }

        override fun onMtuChanged(d: BluetoothDevice, m: Int) = main.post { if (peer?.address == d.address) mtu = m }.let { }

        override fun onDescriptorWriteRequest(
            d: BluetoothDevice, id: Int, desc: BluetoothGattDescriptor, prepared: Boolean, needResp: Boolean, offset: Int, value: ByteArray,
        ) {
            if (needResp) server?.sendResponse(d, id, BluetoothGatt.GATT_SUCCESS, 0, null)
            main.post {
                if (peer?.address == d.address && desc.uuid == CCCD) emit("type" to "connected", "mtu" to mtu, "role" to "host")
            }
        }

        override fun onCharacteristicWriteRequest(
            d: BluetoothDevice, id: Int, c: BluetoothGattCharacteristic, prepared: Boolean, needResp: Boolean, offset: Int, value: ByteArray,
        ) {
            val ok = peer?.address == d.address && c.uuid == RX
            if (needResp) server?.sendResponse(d, id, if (ok) BluetoothGatt.GATT_SUCCESS else BluetoothGatt.GATT_FAILURE, 0, null)
            if (ok) emit("type" to "data", "bytes" to value)
        }

        override fun onNotificationSent(d: BluetoothDevice, status: Int) = main.post { busy = false; pump() }.let { }
    }

    // ---- 게스트 ----

    private fun startScan() {
        stopScan()
        val scanner = adapter?.bluetoothLeScanner ?: throw IllegalStateException("블루투스가 꺼져 있음")
        val filter = ScanFilter.Builder().setServiceUuid(ParcelUuid(SERVICE)).build()
        val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()
        scanner.startScan(listOf(filter), settings, scanCallback)
        scanning = true
        log("방 찾는 중")
    }

    private fun stopScan() {
        if (!scanning) return
        adapter?.bluetoothLeScanner?.stopScan(scanCallback)
        scanning = false
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(type: Int, r: ScanResult) {
            val sd = r.scanRecord?.getServiceData(ParcelUuid(SERVICE)) ?: return // 스캔 응답 전이면 다음 결과를 기다림
            if (sd.size < 4) return
            emit(
                "type" to "room",
                "address" to r.device.address, // 연결용. 화면·로그에는 Dart가 방 ID만 쓴다
                "roomId" to sd.copyOf(4),
                "name" to String(sd, 4, sd.size - 4, Charsets.UTF_8),
                "rssi" to r.rssi,
            )
        }

        override fun onScanFailed(code: Int) {
            main.post { scanning = false }
            emit("type" to "error", "msg" to "스캔 실패 (코드 $code)")
        }
    }

    private fun connect(address: String) {
        stopScan()
        if (gatt != null || peer != null) throw IllegalStateException("이미 연결됨")
        val d = adapter?.getRemoteDevice(address) ?: throw IllegalStateException("블루투스 없음")
        gatt = d.connectGatt(activity, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
        log("연결 시도")
    }

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, state: Int) = main.post {
            if (g != gatt) return@post
            if (state == BluetoothProfile.STATE_CONNECTED) {
                log("연결됨, MTU 협상")
                g.requestMtu(517)
            } else if (state == BluetoothProfile.STATE_DISCONNECTED) {
                g.close()
                gatt = null
                rxChar = null
                resetQueue()
                emit("type" to "disconnected", "status" to status)
            }
        }.let { }

        override fun onMtuChanged(g: BluetoothGatt, m: Int, status: Int) = main.post {
            mtu = if (status == BluetoothGatt.GATT_SUCCESS) m else 23
            log("MTU $mtu")
            g.discoverServices()
        }.let { }

        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) = main.post {
            val s = g.getService(SERVICE)
            val rx = s?.getCharacteristic(RX)
            val tx = s?.getCharacteristic(TX)
            if (rx == null || tx == null) {
                emit("type" to "error", "msg" to "Bit-Chess 서비스가 없음")
                g.disconnect()
                return@post
            }
            rxChar = rx
            g.setCharacteristicNotification(tx, true)
            val cccd = tx.getDescriptor(CCCD)
            val on = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
            if (Build.VERSION.SDK_INT >= 33) {
                g.writeDescriptor(cccd, on)
            } else {
                @Suppress("DEPRECATION")
                cccd.value = on
                @Suppress("DEPRECATION")
                g.writeDescriptor(cccd)
            }
        }.let { }

        override fun onDescriptorWrite(g: BluetoothGatt, d: BluetoothGattDescriptor, status: Int) = main.post {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                emit("type" to "connected", "mtu" to mtu, "role" to "guest")
            } else {
                emit("type" to "error", "msg" to "알림 구독 실패 ($status)")
                g.disconnect()
            }
        }.let { }

        override fun onCharacteristicWrite(g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int) = main.post {
            if (status != BluetoothGatt.GATT_SUCCESS) emit("type" to "error", "msg" to "쓰기 실패 ($status)")
            busy = false
            pump()
        }.let { }

        // Android 13+
        override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic, value: ByteArray) {
            if (c.uuid == TX) emit("type" to "data", "bytes" to value)
        }

        // Android 12 이하
        @Deprecated("Deprecated in Java")
        override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic) {
            if (Build.VERSION.SDK_INT < 33 && c.uuid == TX) {
                @Suppress("DEPRECATION")
                emit("type" to "data", "bytes" to c.value.copyOf())
            }
        }
    }

    // ---- 보내기: 조각 하나씩, 이전 것이 끝나야 다음 ----

    private fun enqueue(chunk: ByteArray) {
        if (chunk.size > minOf(mtu - 3, 512)) throw IllegalArgumentException("조각이 MTU보다 큼: ${chunk.size}")
        if (gatt == null && peer == null) throw IllegalStateException("연결 안 됨")
        queue.addLast(chunk)
        pump()
    }

    private fun pump() {
        if (busy) return
        val chunk = queue.removeFirstOrNull() ?: return
        busy = true
        val ok = gatt?.let { g ->
            val c = rxChar ?: return@let false
            if (Build.VERSION.SDK_INT >= 33) {
                g.writeCharacteristic(c, chunk, BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT) == BluetoothGatt.GATT_SUCCESS
            } else {
                @Suppress("DEPRECATION")
                c.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                @Suppress("DEPRECATION")
                c.value = chunk
                @Suppress("DEPRECATION")
                g.writeCharacteristic(c)
            }
        } ?: peer?.let { d ->
            val c = txChar ?: return@let false
            val s = server ?: return@let false
            if (Build.VERSION.SDK_INT >= 33) {
                s.notifyCharacteristicChanged(d, c, false, chunk) == BluetoothGatt.GATT_SUCCESS
            } else {
                @Suppress("DEPRECATION")
                c.value = chunk
                @Suppress("DEPRECATION")
                s.notifyCharacteristicChanged(d, c, false)
            }
        } ?: false
        if (!ok) {
            busy = false
            resetQueue()
            emit("type" to "error", "msg" to "보내기 실패(연결 상태 확인)")
        }
    }

    private fun resetQueue() {
        queue.clear()
        busy = false
    }

    // ---- 끊기 ----

    private fun disconnect() {
        gatt?.disconnect() // onConnectionStateChange에서 close
        peer?.let { server?.cancelConnection(it) }
    }

    private fun stopAll() {
        stopScan()
        stopAdvertise()
        advData = null
        gatt?.let { it.disconnect(); it.close() }
        gatt = null
        rxChar = null
        peer = null
        server?.close()
        server = null
        txChar = null
        resetQueue()
    }
}
