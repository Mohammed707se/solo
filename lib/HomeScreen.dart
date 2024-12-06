// ignore_for_file: prefer_const_constructors, prefer_const_declarations

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'dart:html' as html;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class Product {
  final String name;
  final int availableCount;
  int downloadCount;
  final TextEditingController controller;

  Product({
    required this.name,
    required this.availableCount,
  })  : downloadCount = 0,
        controller = TextEditingController();

  void dispose() {
    controller.dispose();
  }
}

class Homescreen extends StatefulWidget {
  const Homescreen({super.key});

  @override
  State<Homescreen> createState() => _HomescreenState();
}

class _HomescreenState extends State<Homescreen> {
  Uint8List? _selectedImage;
  bool _isLoading = false;
  String? _response;

  // قائمة المنتجات
  List<Product> _products = [];

  // المتغيرات الأخرى
  String? _downloadError;
  bool _isDownloading = false;
  String? _downloadStatus;
  String? _report;

  // Variables to store coordinates
  double? _latitude;
  double? _longitude;

  // Color palette
  final Color primaryColor = Color(0xFF3AD49E);
  final Color secondaryColor = Color(0xFF003080);
  final Color blackColor = Color(0xFF000000);
  final Color whiteColor = Colors.white;

  @override
  void dispose() {
    // التخلص من كل الـ TextEditingController الخاص بالمنتجات
    for (var product in _products) {
      product.controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      final imageBytes = await pickedFile.readAsBytes();
      setState(() {
        _selectedImage = imageBytes;
        _response = null;
        _products = [];
        _downloadStatus = null;
        _report = null;
        _latitude = null;
        _longitude = null;
      });

      await _sendImageToAPI(imageBytes);
    }
  }

  Future<void> _sendImageToAPI(Uint8List imageBytes) async {
    if (imageBytes.isEmpty) return;

    setState(() {
      _isLoading = true;
      _response = null;
      _products = [];
      _downloadError = null;
      _downloadStatus = null;
      _report = null;
      _latitude = null;
      _longitude = null;
    });

    try {
      final base64Image = base64Encode(imageBytes);
      final url = Uri.parse('https://api.openai.com/v1/chat/completions');
      final apiKey = '';
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      };

      final body = jsonEncode({
        "model": "gpt-4o",
        "messages": [
          {
            "role": "system",
            "content": "أنت خبير في التعرف على المنتجات من الصور فقط."
          },
          {
            "role": "user",
            "content": [
              {
                "type": "text",
                "text":
                    "قم بتحليل الصورة المرفقة وأظهر عدد المنتجات أو الكراتين الموجودة في الصورة على شكل JSON كما يلي: {\"عدد المنتجات\": \"X\", \"وصف المنتجات\": [{\"اسم المنتج\": \"كرتون مياه\", \"العدد\": \"Y\"}, {\"اسم المنتج\": \"علبة عصير\", \"العدد\": \"Z\"}]}.\nإذا لم تكن الصورة واضحة أو لا تحتوي على منتجات أو كراتين، قل \"عذراً الصورة غير واضحة أو ليست بها كراتين أو منتجات\". without ```json"
              },
              {
                "type": "image_url",
                "image_url": {"url": "data:image/png;base64,$base64Image"}
              }
            ]
          }
        ],
        "temperature": 0.0,
      });

      final response = await http.post(url, headers: headers, body: body);

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final content = data['choices'][0]['message']['content'];
        print(content);

        // محاولة تحويل المحتوى إلى JSON
        try {
          final jsonResponse = jsonDecode(content);
          if (jsonResponse.containsKey('عدد المنتجات') &&
              jsonResponse.containsKey('وصف المنتجات')) {
            int? totalProducts =
                int.tryParse(jsonResponse['عدد المنتجات'].toString());
            List<dynamic> productsList = jsonResponse['وصف المنتجات'];

            List<Product> products = productsList.map((product) {
              String name = product['اسم المنتج'];
              int count = int.tryParse(product['العدد'].toString()) ?? 0;
              return Product(name: name, availableCount: count);
            }).toList();

            setState(() {
              _response = content;
              _products = products;
            });
          } else {
            setState(() {
              _response = content;
              _products = [];
            });
          }
        } catch (e) {
          setState(() {
            _response = content;
            _products = [];
          });
        }
      } else {
        setState(() {
          _response = 'خطأ: ${response.statusCode}\n${response.body}';
          _products = [];
        });
      }
    } catch (e) {
      setState(() {
        _response = 'حدث خطأ: $e';
        _products = [];
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _startDownload() async {
    // جمع الأعداد المراد تفريغها لكل منتج
    Map<String, int> downloadRequests = {};
    for (var product in _products) {
      if (product.downloadCount > 0) {
        downloadRequests[product.name] = product.downloadCount;
      }
    }

    if (downloadRequests.isEmpty) {
      setState(() {
        _downloadError = 'يرجى تحديد عدد المنتجات المراد تفريغها لكل نوع.';
      });
      return;
    }

    setState(() {
      _downloadError = null;
      _isDownloading = true;
      _downloadStatus =
          'جاري تفريغ المنتجات... \n الان يتم ارسال امر للرافعة الذكية للانزال (محاكاة)';
      _report = null;
      _latitude = null;
      _longitude = null;
    });

    // انتظار 4 ثوانٍ
    await Future.delayed(Duration(seconds: 4));

    // محاولة الحصول على الموقع
    if (kIsWeb) {
      // على الويب، geolocator يعمل بشكل مختلف
      bool serviceEnabled;
      LocationPermission permission;

      // تحقق من تمكين الخدمة
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _isDownloading = false;
          _downloadStatus = null;
          _report = 'خدمة الموقع غير مفعلة.';
        });
        return;
      }

      // تحقق من صلاحيات الموقع
      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _isDownloading = false;
            _downloadStatus = null;
            _report =
                'تم رفض صلاحية الموقع. يرجى إعادة المحاولة ومنح الصلاحية.';
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _isDownloading = false;
          _downloadStatus = null;
          _report = 'تم رفض صلاحية الموقع بشكل دائم. لا يمكن طلب الصلاحية.';
        });
        return;
      }

      // الحصول على الموقع
      try {
        Position position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high);

        // إنشاء تقرير التفريغ
        String reportText = 'تم تفريغ المنتجات بنجاح.\n';
        downloadRequests.forEach((name, count) {
          reportText += 'المنتج: $name، الكمية: $count\n';
        });

        setState(() {
          _isDownloading = false;
          _downloadStatus = null;
          _report = reportText;
          _latitude = position.latitude;
          _longitude = position.longitude;
        });
      } catch (e) {
        setState(() {
          _isDownloading = false;
          _downloadStatus = null;
          _report = 'حدث خطأ أثناء الحصول على الموقع: $e';
        });
      }
    } else {
      setState(() {
        _isDownloading = false;
        _downloadStatus = null;
        _report = 'هذه الميزة متاحة فقط على الويب.';
      });
    }
  }

  Future<void> _refreshPage() async {
    html.window.location.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: whiteColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        elevation: 0,
        backgroundColor: whiteColor,
        title: Text(
          'SoLo',
          style: TextStyle(
            color: secondaryColor,
            fontWeight: FontWeight.bold,
            fontSize: 24,
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                if (_selectedImage != null)
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: blackColor.withOpacity(0.1),
                          spreadRadius: 2,
                          blurRadius: 5,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: Image.memory(
                        _selectedImage!,
                        height: 250,
                        width: 250,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                SizedBox(height: 30),
                ElevatedButton(
                  onPressed: _pickImage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 3,
                  ),
                  child: Text(
                    'اختيار صورة أو تصوير صورة',
                    style: TextStyle(
                      color: whiteColor,
                      fontSize: 16,
                    ),
                  ),
                ),
                SizedBox(height: 30),
                if (_isLoading)
                  CircularProgressIndicator(
                    color: primaryColor,
                  ),
                if (_response != null && _products.isNotEmpty) ...[
                  SizedBox(height: 20),
                  Container(
                    padding: EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: whiteColor,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: blackColor.withOpacity(0.1),
                          spreadRadius: 1,
                          blurRadius: 3,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'المنتجات المتاحة:',
                          style: TextStyle(
                            color: secondaryColor,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 10),
                        ListView.builder(
                          shrinkWrap: true,
                          physics: NeverScrollableScrollPhysics(),
                          itemCount: _products.length,
                          itemBuilder: (context, index) {
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8.0),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      _products[index].name,
                                      style: TextStyle(
                                        color: secondaryColor,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: Text(
                                      'متاح: ${_products[index].availableCount}',
                                      style: TextStyle(
                                        color: secondaryColor,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  Expanded(
                                    flex: 2,
                                    child: TextField(
                                      controller: _products[index].controller,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                        labelText: 'الكمية',
                                        border: OutlineInputBorder(),
                                        errorText: (_products[index]
                                                    .downloadCount >
                                                _products[index].availableCount)
                                            ? 'أكبر من المتاح'
                                            : null,
                                      ),
                                      onChanged: (value) {
                                        setState(() {
                                          int? count = int.tryParse(value);
                                          if (count != null &&
                                              count <=
                                                  _products[index]
                                                      .availableCount &&
                                              count >= 0) {
                                            _products[index].downloadCount =
                                                count;
                                            print(
                                                'Product: ${_products[index].name}, Download Count: ${_products[index].downloadCount}');
                                          } else {
                                            _products[index].downloadCount = 0;
                                            _products[index].controller.text =
                                                '';
                                            print(
                                                'Product: ${_products[index].name}, Invalid Download Count Set to 0');
                                          }
                                        });
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: _isDownloading ? null : _startDownload,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            padding: EdgeInsets.symmetric(
                                horizontal: 30, vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 3,
                          ),
                          child: Text(
                            'تفريغ',
                            style: TextStyle(
                              color: whiteColor,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        if (_downloadError != null) ...[
                          SizedBox(height: 10),
                          Text(
                            _downloadError!,
                            style: TextStyle(
                              color: Colors.red,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                if (_downloadStatus != null) ...[
                  SizedBox(height: 20),
                  Text(
                    _downloadStatus!,
                    style: TextStyle(
                      color: secondaryColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (_isDownloading) SizedBox(height: 20),
                if (_isDownloading)
                  CircularProgressIndicator(
                    color: primaryColor,
                  ),
                if (_report != null) ...[
                  SizedBox(height: 20),
                  Container(
                    padding: EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: whiteColor,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: blackColor.withOpacity(0.1),
                          spreadRadius: 1,
                          blurRadius: 3,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Text(
                          'التقرير:',
                          style: TextStyle(
                            color: secondaryColor,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 10),
                        Text(
                          _report!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: secondaryColor,
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(height: 20),
                        if (_latitude != null && _longitude != null)
                          Container(
                            height: 300,
                            child: FlutterMap(
                              options: MapOptions(
                                center: LatLng(_latitude!, _longitude!),
                                zoom: 15.0,
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate:
                                      "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                                  subdomains: ['a', 'b', 'c'],
                                ),
                                MarkerLayer(
                                  markers: [
                                    Marker(
                                      width: 80.0,
                                      height: 80.0,
                                      point: LatLng(_latitude!, _longitude!),
                                      child: Icon(
                                        Icons.location_pin,
                                        color: Colors.red,
                                        size: 40,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        if (_report!.startsWith('تم رفض')) SizedBox(height: 10),
                        if (_report!.startsWith('تم رفض'))
                          ElevatedButton(
                            onPressed: _refreshPage,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              padding: EdgeInsets.symmetric(
                                  horizontal: 30, vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 3,
                            ),
                            child: Text(
                              'تحديث الصفحة',
                              style: TextStyle(
                                color: whiteColor,
                                fontSize: 16,
                              ),
                            ),
                          ),
                      ],
                    ),
                  )
                ]
              ],
            ),
          ),
        ),
      ),
    );
  }
}
