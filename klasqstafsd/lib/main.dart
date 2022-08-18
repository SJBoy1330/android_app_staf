import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:klasqstafsd/popup.dart';

import 'dart:io';
import 'dart:ui';
import 'dart:async';
import 'dart:isolate';

import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:geolocator/geolocator.dart' as locator;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  AwesomeNotifications().initialize(
    null,
    [
      NotificationChannel(
        channelKey: 'fcm_notif',
        channelName: 'FCM Notification',
        channelDescription: 'Notifications from FCM',
        playSound: true,
        soundSource: 'resource://raw/notifikasi_android_sd',
        enableLights: true,
        enableVibration: true,
      ),
    ]
  );

  await FlutterDownloader.initialize(debug: true);
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseMessaging.onMessage.listen((RemoteMessage message) => fcmNotification(message));
  FirebaseMessaging.onBackgroundMessage(fcmNotification);

  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp])
    .then((value) => runApp(const MyApp()));
}

Future<void> fcmNotification(RemoteMessage message) async {
  print("Handling a background message: ${message.messageId}");
  print("Message : ${message.notification!.title}");
  
  if (message.notification != null) {
    AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: 0,
        channelKey: "fcm_notif",
        title: message.notification!.title,
        body: message.notification!.body,
        color: const Color(0xFFFFF8F8),
        customSound: 'resource://raw/notifikasi_android_sd',
      ),
    );
  }
}

class MyApp extends StatefulWidget {
  const MyApp({ Key? key }) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late PullToRefreshController refreshController;
  InAppWebViewController? _webViewController;
  CookieManager cookieManager = CookieManager.instance();

  String mainURL = "https://sd.klasq.id/app_staf/";
  double loadProgress = 0;
  bool isLocationGranted = false;
  bool isStorageGranted = false;
  bool isErrorLoading = false;
  bool isCurrentlyLoading = false;
  bool isPullReload = false;
  bool needsUpdate = false;

  DateTime currentBackPressTime = DateTime.now();
  
  ReceivePort _port = ReceivePort();
  late DownloadTaskStatus downloadStatus;

  @override
  void initState() {
    super.initState();

    checkVersion();
    
    refreshController = PullToRefreshController(
      onRefresh: () async {
        _webViewController?.reload();
      },
      options: PullToRefreshOptions(
        color: Colors.blueAccent,
        enabled: true,
      ),
    );

    IsolateNameServer.registerPortWithName(_port.sendPort, 'downloader_send_port');
    _port.listen((dynamic data) {
      String id = data[0];
      DownloadTaskStatus status = data[1];
      int progress = data[2];

      setState(() => downloadStatus = status );
    });

    FlutterDownloader.registerCallback(downloadCallback);
  }

  @override
  void dispose() {
    IsolateNameServer.removePortNameMapping('downloader_send_port');
    super.dispose();
  }

  @pragma('vm:entry-point')
  static void downloadCallback(String id, DownloadTaskStatus status, int progress) {
    final SendPort? send = IsolateNameServer.lookupPortByName('downloader_send_port');
    send!.send([id, status, progress]);
  }

  void checkVersion() async {
    PackageInfo appInfo = await PackageInfo.fromPlatform();

    await cookieManager.setCookie(
      url: Uri.parse(mainURL),
      name: "APP_VER",
      value: appInfo.version,
    );
  }

  void setPosCookies() async {
    // Longitude & Latitude
    await _checkLocationPermission();
    if (isLocationGranted) {
      locator.Position pos = await locator.Geolocator.getCurrentPosition();

      await cookieManager.setCookie(
        url: Uri.parse(mainURL),
        name: "LAT",
        value: "${pos.latitude}",
      );
      await cookieManager.setCookie(
        url: Uri.parse(mainURL),
        name: "LONG",
        value: "${pos.longitude}",
      );
    }

    // Device Info
    String id = "";
    int width = window.physicalSize.width.toInt();
    int height = window.physicalSize.height.toInt();

    var info = DeviceInfoPlugin();
    if (Platform.isIOS) {
      var iosDeviceInfo = await info.iosInfo;
      id = iosDeviceInfo.identifierForVendor!;
      String os = iosDeviceInfo.systemVersion!;
      String model = iosDeviceInfo.model!;
      
      await cookieManager.setCookie(
        url: Uri.parse(mainURL),
        name: "DEVICE_INFO",
        value: "RESOLUSI:${width}X$height#OS:$os#ID:$id#BRAND:iPhone#MANUFACTURER:Apple#MODEL:$model#PRODUCT:apple",
      );
    } else {
      var androidDeviceInfo = await info.androidInfo;
      id = androidDeviceInfo.androidId!;
      String os = androidDeviceInfo.version.release!;
      String brand = androidDeviceInfo.brand!;
      String manufacturer = androidDeviceInfo.manufacturer!;
      String model = androidDeviceInfo.model!;
      String product = androidDeviceInfo.product!;
      
      await cookieManager.setCookie(
        url: Uri.parse(mainURL),
        name: "DEVICE_INFO",
        value: "RESOLUSI:${width}X$height#OS:$os#ID:$id#BRAND:$brand#MANUFACTURER:$manufacturer#MODEL:$model#PRODUCT:$product",
      );
    }

    // FCM Token
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    
    await cookieManager.setCookie(
      url: Uri.parse(mainURL),
      name: "FCM_TOKEN",
      value: "${await messaging.getToken()}",
    );
  }

  Future<void> _checkLocationPermission() async {
    final serviceStatus = await Permission.locationWhenInUse.serviceStatus;
    final isGpsOn = serviceStatus == ServiceStatus.enabled;
    if (!isGpsOn) {
      return;
    }

    final status = await Permission.locationWhenInUse.request();
    if (status == PermissionStatus.granted) {
      isLocationGranted = true;
    } else if (status == PermissionStatus.denied) {
      isLocationGranted = false;

      Fluttertoast.showToast(
        msg: 'Ijin lokasi ditolak, ijin dibutuhkan untuk jalannya aplikasi.',
        backgroundColor: const Color.fromARGB(200, 0, 0, 0),
      );
    } else if (status == PermissionStatus.permanentlyDenied) {
      isLocationGranted = false;
      
      Fluttertoast.showToast(
        msg: 'Mengarahkan ke pengaturan...',
        backgroundColor: const Color.fromARGB(200, 0, 0, 0),
      );
      await openAppSettings();
    }
  }

  // Store cookies to save user session for download
  String cookiesString = '';
  Future<void> updateCookies(Uri url) async {
    List<Cookie> cookies = await CookieManager().getCookies(url: url);
    cookiesString = '';
    for (Cookie cookie in cookies) {
      cookiesString += '${cookie.name}=${cookie.value};';
    }
    print("cookies : " + cookiesString);
  }

  Future<String> createFileInAppSpecificDir(String filename, String savedDir) async {
    File newFile = File('$savedDir/$filename');
    String fileName = filename;
    try {
      var i = 0;
      while (true) {
        i += 1;
        print('Filename : $newFile');

        var rs = await newFile.exists();
        if (!rs) {
          return fileName;
        } else {
          newFile = File('$savedDir/$filename ($i)');
          fileName = '$filename ($i)';
        }
      }
    } catch (e) {
      print("Create a file using java.io API failed ");
    }
    return filename;
  }

  Future downloadFile(DownloadStartRequest downloadRequest, String filename) async {
    await FlutterDownloader.enqueue(
      url: downloadRequest.url.toString(),
      fileName: filename,
      savedDir: '/storage/emulated/0/Download',
      showNotification: true,
      saveInPublicStorage: true,
      openFileFromNotification: true,
      headers: {
        HttpHeaders.userAgentHeader: downloadRequest.userAgent!,
        HttpHeaders.contentTypeHeader: downloadRequest.mimeType!,
        HttpHeaders.cookieHeader: cookiesString,
      },
    );
  }

  Future<bool> onWillPop() async {
    DateTime now = DateTime.now();
    Uri? currentUri = await _webViewController!.getUrl();
    
    if (currentUri == Uri.parse(mainURL + 'home')) {
      if (now.difference(currentBackPressTime) > Duration(seconds: 2)) {
        currentBackPressTime = now;
        Fluttertoast.showToast(
          msg: 'Tekan kembali lagi untuk keluar aplikasi',
          backgroundColor: const Color.fromARGB(200, 0, 0, 0),
        );

        return Future.value(false);
      }
    } 
    else {
      if (await _webViewController!.canGoBack()) {
        await _webViewController!.loadUrl(
          urlRequest: URLRequest(url: Uri.parse("${mainURL}home"))
        );
      }

      return Future.value(false);
    }

    return Future.value(true);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "KlasQ Staf SD",
      debugShowCheckedModeBanner: false,
      home: Builder(
        builder: (context) {
          return Scaffold(
            resizeToAvoidBottomInset: true,
            body: WillPopScope(
              onWillPop: onWillPop,
              child: SafeArea(
                child: Stack(
                  children: [
                    InAppWebView(
                      initialUrlRequest: URLRequest(url: Uri.parse(mainURL)),
                      initialOptions: InAppWebViewGroupOptions(
                        crossPlatform: InAppWebViewOptions(
                          javaScriptEnabled: true,
                          javaScriptCanOpenWindowsAutomatically: true,
                          useOnDownloadStart: true,
                          allowFileAccessFromFileURLs: true,
                          allowUniversalAccessFromFileURLs: true,
                          useShouldOverrideUrlLoading: true,
                        ),
                        android: AndroidInAppWebViewOptions(
                          allowFileAccess: true,
                          allowContentAccess: true,
                          useHybridComposition: true,
                          clearSessionCache: true,
                          domStorageEnabled: true,
                        ),
                      ),
                      onWebViewCreated: (InAppWebViewController controller) {
                        _webViewController = controller;
                      },
                      pullToRefreshController: refreshController,
                      onLoadStart: (controller, url) {
                        if (url.toString() != mainURL) {
                          setPosCookies();
                        }

                        setState(() => isCurrentlyLoading = false);
                      },
                      onLoadStop: (controller, url) async {
                        refreshController.endRefreshing();
                        
                        if (url != null) {
                          await updateCookies(url);
                        }
                        
                        setState(() {
                          isCurrentlyLoading = false;
                          isPullReload = false;
                        });
                      },
                      onLoadError: (controller, url, code, message) {
                        setState(() {
                          isErrorLoading = true;
                        });
                        
                        Fluttertoast.showToast(
                          msg: 'Gagal Memuat Halaman',
                          backgroundColor: const Color.fromARGB(145, 0, 0, 0),
                        );
                      },
                      shouldOverrideUrlLoading: (controller, action) async {
                        var uri = action.request.url!;
                        print("url : " + uri.toString());

                        if ( !(uri.toString()).startsWith("https://sd.klasq.id") ) {
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                            return NavigationActionPolicy.CANCEL;
                          } else {
                            print("link doesn't work");
                          }
                        }
                        
                        return NavigationActionPolicy.ALLOW;
                      },
                      onProgressChanged: (controller, progress) {
                        setState(() => loadProgress = progress / 100);
                      },
                      onDownloadStartRequest: (controller, downloadRequest) async {               
                        List<String> content = downloadRequest.contentDisposition!.split('=');
                        String filename = content[1];
                        
                        final status = await Permission.storage.request();
                        if (status == PermissionStatus.granted) {
                          isStorageGranted = true;
                        
                          String name = await createFileInAppSpecificDir(filename, '/storage/emulated/0/Download');
                          await downloadFile(downloadRequest, name);
                        
                          Fluttertoast.showToast(
                            msg: 'Download Mulai',
                            backgroundColor: const Color.fromARGB(200, 0, 0, 0),
                          );
                        } else if (status == PermissionStatus.denied) {
                          isStorageGranted = false;
                        
                          Fluttertoast.showToast(
                            msg: 'Ijin penyimpanan ditolak, download dibatalkan.',
                            backgroundColor: const Color.fromARGB(200, 0, 0, 0),
                          );
                        } else if (status == PermissionStatus.permanentlyDenied) {
                          isStorageGranted = false;
                        
                          Fluttertoast.showToast(
                            msg: 'Mengarahkan ke pengaturan untuk ijin penyimpanan.',
                            backgroundColor: const Color.fromARGB(200, 0, 0, 0),
                          );
                          await openAppSettings();
                        }
                        
                      },
                      androidOnGeolocationPermissionsShowPrompt: (controller, origin) async {
                        if (isLocationGranted == true) {
                          return Future.value(GeolocationPermissionShowPromptResponse(
                              origin: origin, allow: true, retain: true));
                        } else {
                          return Future.value(GeolocationPermissionShowPromptResponse(
                              origin: origin, allow: false, retain: false));
                        }
                      },
                    ),
                    isCurrentlyLoading ? LinearProgressIndicator(
                      value: loadProgress,
                      color: const Color(0xFFEC3528),
                    ) : const SizedBox(height: 0),
                    isErrorLoading ? Container(
                      color: const Color(0xFFFFF8F8),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset(
                            'assets/images/no_conn_img.png',
                            fit: BoxFit.cover,
                            alignment: Alignment.center,
                          ),
                          const Text(
                            "Koneksi tidak tersedia",
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold
                            ),
                          ),
                          const SizedBox(height: 10),
                          const SizedBox(
                            width: 240,
                            child: Text(
                              "Silahkan periksa jaringan internet anda dan coba lagi",
                              style: TextStyle(
                                color: Color.fromARGB(141, 126, 126, 126),
                                fontSize: 16,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(builder: (BuildContext context) => const MyApp())
                              );
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('Coba Lagi'),
                            style: ElevatedButton.styleFrom(
                              primary: Colors.redAccent,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
                            ),
                          ),
                        ],
                      ),
                    ) : const SizedBox(height: 0),
                    needsUpdate ? Container(
                      color: const Color.fromARGB(130, 0, 0, 0),
                      child: const UpdatePopup(),
                    ) : const SizedBox(height: 0),
                  ],
                ),
              ),
            ),
          );
        }
      ),
    );
  }
}