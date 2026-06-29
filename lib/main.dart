import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'services/gemini_crop_doctor_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const KasiAiApp());
}

class KasiAiApp extends StatelessWidget {
  const KasiAiApp({super.key});

  @override
  Widget build(BuildContext context) {
    final khmerTheme = GoogleFonts.notoSansKhmerTextTheme();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'កសិAI',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.green),
        scaffoldBackgroundColor: AppColors.background,
        useMaterial3: true,
        textTheme: khmerTheme,
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.green,
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 0,
          titleTextStyle: GoogleFonts.moul(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: GoogleFonts.notoSansKhmer(fontWeight: FontWeight.bold),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.green, width: 1.8),
          ),
        ),
      ),
      home: const SplashScreenPage(),
    );
  }
}


class SplashScreenPage extends StatefulWidget {
  const SplashScreenPage({super.key});

  @override
  State<SplashScreenPage> createState() => _SplashScreenPageState();
}

class _SplashScreenPageState extends State<SplashScreenPage> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AuthGate()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B5D24),
      body: SizedBox.expand(
        child: Image.asset(
          'assets/images/splash_screen.png',
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}


class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF0B5D24),
            body: Center(child: CircularProgressIndicator(color: Colors.white)),
          );
        }

        if (snapshot.hasData) {
          return const AppShell();
        }

        return const LoginPage();
      },
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isRegister = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.length < 6 || (_isRegister && name.isEmpty)) {
      setState(() => _errorMessage = 'សូមបញ្ចូលព័ត៌មានឱ្យបានត្រឹមត្រូវ។ Password ត្រូវមានយ៉ាងតិច 6 តួអក្សរ។');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_isRegister) {
        final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        final user = credential.user;
        if (user != null) {
          await user.updateDisplayName(name);
          await ensureUserDocument(user, name: name);
        }
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      }
    } on FirebaseAuthException catch (error) {
      setState(() => _errorMessage = _authErrorMessage(error));
    } catch (error) {
      setState(() => _errorMessage = 'មានបញ្ហា: $error');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }


  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      const webClientId = '500628703275-ti591019uqbud4dhenvh5hd8mrrcuq0p.apps.googleusercontent.com';

      final googleSignIn = GoogleSignIn(
        scopes: <String>['email', 'profile'],
        serverClientId: Platform.isAndroid ? webClientId : null,
      );

      await googleSignIn.signOut();
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCredential.user;
      if (user != null) {
        await ensureUserDocument(
          user,
          name: googleUser.displayName,
          photoUrl: googleUser.photoUrl,
        );
      }
    } on FirebaseAuthException catch (error) {
      setState(() => _errorMessage = _authErrorMessage(error));
    } on PlatformException catch (error) {
      final message = error.message ?? error.toString();
      if (error.code == 'sign_in_failed' && message.contains('10')) {
        setState(() => _errorMessage =
            'Google Login មិនទាន់ configure ត្រឹមត្រូវទេ។ សូមបន្ថែម SHA-1/SHA-256 ក្នុង Firebase Project Settings រួច download google-services.json ថ្មី។');
      } else {
        setState(() => _errorMessage = 'Google Login មិនដំណើរការ: ${error.message ?? error.code}');
      }
    } catch (error) {
      setState(() => _errorMessage = 'Google Login មិនដំណើរការ: $error');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _authErrorMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'email-already-in-use':
        return 'Email នេះមានគណនីរួចហើយ។';
      case 'invalid-email':
        return 'Email មិនត្រឹមត្រូវ។';
      case 'weak-password':
        return 'Password ខ្សោយពេក។ សូមប្រើយ៉ាងតិច 6 តួអក្សរ។';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email ឬ Password មិនត្រឹមត្រូវ។';
      case 'network-request-failed':
        return 'មិនអាចភ្ជាប់ Internet បាន។';
      default:
        return error.message ?? 'មិនអាចចូលគណនីបានទេ។';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 28),
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Image.asset('assets/images/app_icon.png', width: 96, height: 96, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                _isRegister ? 'បង្កើតគណនី KasiAI' : 'ចូលគណនី KasiAI',
                textAlign: TextAlign.center,
                style: GoogleFonts.moul(fontSize: 25, color: AppColors.darkGreen),
              ),
              const SizedBox(height: 8),
              Text(
                'រក្សាទុកទិន្នន័យដាំដុះ និងទស្សន៍ទាយការផ្គត់ផ្គង់តាមគណនីរបស់អ្នក',
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKhmer(color: AppColors.muted, height: 1.6),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: cardDecoration(),
                child: Column(
                  children: [
                    if (_isRegister) ...[
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(labelText: 'ឈ្មោះ'),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                        ),
                      ),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEBEE),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFFFCDD2)),
                        ),
                        child: Text(_errorMessage!, style: GoogleFonts.notoSansKhmer(color: AppColors.danger, height: 1.5)),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isLoading ? null : _submit,
                        icon: _isLoading
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Icon(_isRegister ? Icons.person_add_alt_1 : Icons.login),
                        label: Text(_isRegister ? 'បង្កើតគណនី' : 'ចូលគណនី'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _isLoading ? null : _signInWithGoogle,
                        icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
                        label: const Text('ចូលដោយ Google'),
                      ),
                    ),
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () => setState(() {
                                _isRegister = !_isRegister;
                                _errorMessage = null;
                              }),
                      child: Text(_isRegister ? 'មានគណនីរួចហើយ? ចូលគណនី' : 'មិនទាន់មានគណនី? បង្កើតគណនី'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppColors {
  static const Color green = Color(0xFF2E7D32);
  static const Color darkGreen = Color(0xFF1B5E20);
  static const Color lightGreen = Color(0xFFE8F5E9);
  static const Color background = Color(0xFFF5F8F2);
  static const Color amber = Color(0xFFFFC107);
  static const Color border = Color(0xFFE0EAD9);
  static const Color text = Color(0xFF263238);
  static const Color muted = Color(0xFF607D8B);
  static const Color danger = Color(0xFFD84315);
}


const List<String> kCambodianProvinces = [
  'រាជធានីភ្នំពេញ',
  'កណ្ដាល',
  'កំពង់ចាម',
  'ត្បូងឃ្មុំ',
  'កំពង់ធំ',
  'កំពង់ឆ្នាំង',
  'កំពង់ស្ពឺ',
  'កំពត',
  'កែប',
  'កោះកុង',
  'ក្រចេះ',
  'តាកែវ',
  'ព្រៃវែង',
  'ពោធិ៍សាត់',
  'បាត់ដំបង',
  'បន្ទាយមានជ័យ',
  'ប៉ៃលិន',
  'សៀមរាប',
  'ឧត្តរមានជ័យ',
  'ព្រះវិហារ',
  'ស្ទឹងត្រែង',
  'រតនគិរី',
  'មណ្ឌលគិរី',
  'ព្រះសីហនុ',
  'ស្វាយរៀង',
];

const List<String> kCambodianCrops = [
  'ស្រូវ',
  'ម្ទេស',
  'ប៉េងប៉ោះ',
  'ស្ពៃ',
  'ត្រសក់',
  'ត្រប់',
  'សណ្តែកគួរ',
  'សណ្តែកសៀង',
  'សណ្តែកដី',
  'ពោត',
  'ដំឡូងមី',
  'ដំឡូងជ្វា',
  'អំពៅ',
  'ល្ង',
  'កៅស៊ូ',
  'ម្រេច',
  'ស្វាយ',
  'ចេក',
  'ដូង',
  'ស្វាយចន្ទី',
  'ទុរេន',
  'មង្ឃុត',
  'មៀន',
  'ក្រូច',
  'ឪឡឹក',
  'ម្នាស់',
  'ល្ហុង',
  'ត្រឡាច',
  'ខ្ទឹមស',
  'ខ្ទឹមក្រហម',
  'ខ្ញី',
  'រមៀត',
];

const List<String> kUserRoles = [
  'កសិករ',
  'អ្នកទិញ',
  'កសិករ និងអ្នកទិញ',
];

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  int _nextId = 100;

  final List<ScanRecord> _scanRecords = [
    ScanRecord(
      crop: 'ម្ទេស',
      disease: 'Leaf Spot',
      severity: 'Medium',
      confidence: 0.87,
      recommendation: 'កាត់ស្លឹកដែលឆ្លងចេញ បន្ថយការស្រោចទឹកលើស និងបង្កើនចន្លោះខ្យល់។',
      createdAt: DateTime.now().subtract(const Duration(hours: 5)),
    ),
  ];

  final List<PlantingRecord> _plantingRecords = [];

  final List<ProductListing> _products = [
    ProductListing(
      id: 1,
      crop: 'ស្វាយចន្ទី',
      province: 'កំពង់ធំ',
      quantity: 2000,
      unit: 'kg',
      price: 1.20,
      grade: 'Grade A',
      harvestDate: DateTime(2026, 6, 15),
      farmerName: 'កសិករ សុភា',
    ),
    ProductListing(
      id: 2,
      crop: 'ប៉េងប៉ោះ',
      province: 'កណ្តាល',
      quantity: 650,
      unit: 'kg',
      price: 0.85,
      grade: 'Grade A',
      harvestDate: DateTime(2026, 7, 1),
      farmerName: 'កសិករ វណ្ណា',
    ),
  ];

  final List<BuyingDemand> _demands = [
    BuyingDemand(
      id: 1,
      crop: 'ប៉េងប៉ោះ',
      province: 'ភ្នំពេញ',
      quantity: 500,
      unit: 'kg/week',
      targetPrice: 0.90,
      buyerName: 'ភោជនីយដ្ឋាន Green Food',
      deliveryDate: DateTime(2026, 7, 3),
    ),
  ];

  final List<DealRecord> _deals = [];
  final List<ProfitRecord> _profitRecords = [
    ProfitRecord(title: 'ថ្លៃពូជម្ទេស', type: ProfitType.expense, amount: 75),
    ProfitRecord(title: 'ថ្លៃជី', type: ProfitType.expense, amount: 110),
    ProfitRecord(title: 'លក់ម្ទេស', type: ProfitType.income, amount: 520),
  ];

  void _changeTab(int index) {
    setState(() => _selectedIndex = index);
  }

  void _addScan(ScanRecord record) {
    setState(() {
      _scanRecords.insert(0, record);
      if (_scanRecords.length > 20) {
        _scanRecords.removeRange(20, _scanRecords.length);
      }
    });
  }

  void _addPlanting(PlantingRecord record) {
    setState(() => _plantingRecords.insert(0, record));
  }

  void _addProduct(ProductListing product) {
    setState(() => _products.insert(0, product));
  }

  void _addDemand(BuyingDemand demand) {
    setState(() => _demands.insert(0, demand));
  }

  void _addProfit(ProfitRecord record) {
    setState(() => _profitRecords.insert(0, record));
  }

  int _generateId() {
    _nextId += 1;
    return _nextId;
  }

  void _createDealFromProduct(ProductListing product) {
    final value = product.quantity * product.price;
    final commission = value * 0.02;
    final deal = DealRecord(
      id: _generateId(),
      crop: product.crop,
      buyerName: 'អ្នកទិញដុំ Demo',
      farmerName: product.farmerName,
      quantity: product.quantity,
      value: value,
      commission: commission,
      status: 'Completed',
    );
    setState(() => _deals.insert(0, deal));
  }

  void _createDealFromDemand(BuyingDemand demand) {
    final value = demand.quantity * demand.targetPrice;
    final commission = value * 0.02;
    final deal = DealRecord(
      id: _generateId(),
      crop: demand.crop,
      buyerName: demand.buyerName,
      farmerName: 'កសិករ Demo',
      quantity: demand.quantity,
      value: value,
      commission: commission,
      status: 'Pending',
    );
    setState(() => _deals.insert(0, deal));
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(
        onNavigate: _changeTab,
        onProfile: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfilePage())),
        userEmail: FirebaseAuth.instance.currentUser?.email ?? '',
        scanCount: _scanRecords.length,
        productCount: _products.length,
        demandCount: _demands.length,
        dealCount: _deals.length,
      ),
      AiDoctorPage(records: _scanRecords, onAddScan: _addScan),
      PlantingPage(records: _plantingRecords, onAddRecord: _addPlanting, generateId: _generateId),
      MarketplacePage(
        products: _products,
        demands: _demands,
        deals: _deals,
        onAddProduct: _addProduct,
        onAddDemand: _addDemand,
        onCreateDealFromProduct: _createDealFromProduct,
        onCreateDealFromDemand: _createDealFromDemand,
        generateId: _generateId,
      ),
      DashboardPage(
        scans: _scanRecords,
        plantings: _plantingRecords,
        products: _products,
        demands: _demands,
        deals: _deals,
        profitRecords: _profitRecords,
        onAddProfit: _addProfit,
      ),
    ];

    return Scaffold(
      body: pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        selectedItemColor: AppColors.green,
        unselectedItemColor: AppColors.muted,
        type: BottomNavigationBarType.fixed,
        onTap: _changeTab,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'ទំព័រដើម'),
          BottomNavigationBarItem(icon: Icon(Icons.camera_alt_rounded), label: 'AI ស្កេន'),
          BottomNavigationBarItem(icon: Icon(Icons.insights_rounded), label: 'ដាំដុះ'),
          BottomNavigationBarItem(icon: Icon(Icons.storefront_rounded), label: 'ផ្សារ'),
          BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: 'ផ្ទាំង'),
        ],
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.onNavigate,
    required this.onProfile,
    required this.userEmail,
    required this.scanCount,
    required this.productCount,
    required this.demandCount,
    required this.dealCount,
  });

  final ValueChanged<int> onNavigate;
  final VoidCallback onProfile;
  final String userEmail;
  final int scanCount;
  final int productCount;
  final int demandCount;
  final int dealCount;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        leadingWidth: 104,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Dashboard',
              onPressed: () => onNavigate(4),
              icon: const Icon(Icons.dashboard_rounded),
            ),
            IconButton(
              tooltip: 'Profile',
              onPressed: onProfile,
              icon: const Icon(Icons.account_circle_rounded),
            ),
          ],
        ),
        title: Text('កសិAI', style: GoogleFonts.moul(fontSize: 24)),
        actions: [
          const NotificationBell(),
          IconButton(
            tooltip: 'Logout',
            onPressed: () async {
              await GoogleSignIn().signOut();
              await FirebaseAuth.instance.signOut();
            },
            icon: const Icon(Icons.logout_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const HeroBanner(),
              const SizedBox(height: 12),
              HomeProfileCard(onProfile: onProfile),
              const SizedBox(height: 20),
              FirestoreHomeStats(scanCount: scanCount),
              const SizedBox(height: 24),
              SectionTitle(title: 'មុខងារសំខាន់ៗ', actionLabel: 'ផ្ទាំង', onAction: () => onNavigate(4)),
              const SizedBox(height: 12),
              FeatureCard(
                icon: Icons.camera_alt,
                title: 'AI Crop Doctor',
                description: 'ថតរូប/ជ្រើសរោគសញ្ញា ដើម្បីឱ្យ AI ជួយពិនិត្យជំងឺ និងណែនាំជាភាសាខ្មែរ។',
                onTap: () => onNavigate(1),
              ),
              FeatureCard(
                icon: Icons.insights,
                title: 'Crop Supply Predictor',
                description: 'បញ្ចូលថ្ងៃដាំ ផ្ទៃដី និងថ្ងៃប្រមូលផល ដើម្បីទស្សន៍ទាយការផ្គត់ផ្គង់ទីផ្សារ។',
                onTap: () => onNavigate(2),
              ),
              FeatureCard(
                icon: Icons.storefront,
                title: 'Smart Marketplace',
                description: 'ភ្ជាប់កសិករជាមួយអ្នកទិញដុំ ដោយប្រើ product listing និង buying demand។',
                onTap: () => onNavigate(3),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => onNavigate(1),
                icon: const Icon(Icons.camera),
                label: Text('ចាប់ផ្តើមស្កេនដំណាំ', style: GoogleFonts.notoSansKhmer(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.amber,
        foregroundColor: AppColors.darkGreen,
        onPressed: () => onNavigate(3),
        icon: const Icon(Icons.add),
        label: Text('បង្ហោះផលិតផល', style: GoogleFonts.notoSansKhmer(fontWeight: FontWeight.bold)),
      ),
    );
  }
}


class FirestoreHomeStats extends StatelessWidget {
  const FirestoreHomeStats({super.key, required this.scanCount});

  final int scanCount;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('scan_records')
          .where('userId', isEqualTo: user.uid)
          .snapshots(),
      builder: (context, scanSnapshot) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('product_listings')
              .where('userId', isEqualTo: user.uid)
              .snapshots(),
          builder: (context, productSnapshot) {
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('buying_demands')
                  .where('userId', isEqualTo: user.uid)
                  .snapshots(),
              builder: (context, demandSnapshot) {
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance.collection('deals').snapshots(),
                  builder: (context, dealSnapshot) {
                    final cloudScanCount = scanSnapshot.data?.docs.length ?? 0;
                    final myScanCount = cloudScanCount > 0 ? cloudScanCount : scanCount;
                    final productCount = productSnapshot.data?.docs.length ?? 0;
                    final demandCount = demandSnapshot.data?.docs.length ?? 0;
                    final dealCount = (dealSnapshot.data?.docs ?? [])
                        .where((doc) {
                          final data = doc.data();
                          return data['buyerId'] == user.uid || data['farmerId'] == user.uid;
                        })
                        .length;
                    return Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: StatCard(title: 'AI Scan', value: '$myScanCount', icon: Icons.camera_alt)),
                            const SizedBox(width: 12),
                            Expanded(child: StatCard(title: 'ផលិតផលខ្ញុំ', value: '$productCount', icon: Icons.eco)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: StatCard(title: 'តម្រូវការខ្ញុំ', value: '$demandCount', icon: Icons.shopping_bag)),
                            const SizedBox(width: 12),
                            Expanded(child: StatCard(title: 'Deal ខ្ញុំ', value: '$dealCount', icon: Icons.handshake)),
                          ],
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class HeroBanner extends StatelessWidget {
  const HeroBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [AppColors.darkGreen, AppColors.green, Color(0xFF66BB6A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.25),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.eco, color: Colors.white, size: 38),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'KhmerFarm Link AI',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'AI ជួយកសិករ ដាំឱ្យល្អ លក់ឱ្យបានតម្លៃ',
            style: GoogleFonts.notoSansKhmer(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'ពិនិត្យជំងឺដំណាំ • ទស្សន៍ទាយទីផ្សារ • ភ្ជាប់អ្នកទិញដុំ',
            style: GoogleFonts.notoSansKhmer(
              color: Colors.white.withOpacity(0.95),
              fontSize: 14,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}


class HomeProfileCard extends StatelessWidget {
  const HomeProfileCard({super.key, required this.onProfile});

  final VoidCallback onProfile;

  ImageProvider? _profileImage(Map<String, dynamic> data, User user) {
    final photoBase64 = data['photoBase64']?.toString() ?? '';
    if (photoBase64.isNotEmpty) {
      try {
        return MemoryImage(base64Decode(photoBase64));
      } catch (_) {}
    }

    final photoUrl = data['photoUrl']?.toString() ?? user.photoURL ?? '';
    if (photoUrl.isNotEmpty) return NetworkImage(photoUrl);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? <String, dynamic>{};
        final name = (data['name']?.toString().trim().isNotEmpty == true)
            ? data['name'].toString()
            : (user.displayName?.trim().isNotEmpty == true ? user.displayName! : 'KasiAI User');
        final email = data['email']?.toString() ?? user.email ?? '';
        final phone = data['phone']?.toString() ?? '';
        final province = data['province']?.toString() ?? '';
        final role = data['role']?.toString() ?? '';
        final imageProvider = _profileImage(data, user);

        return InkWell(
          onTap: onProfile,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.lightGreen,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: Colors.white,
                  backgroundImage: imageProvider,
                  child: imageProvider == null ? const Icon(Icons.person_rounded, color: AppColors.green, size: 30) : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.notoSansKhmer(fontWeight: FontWeight.bold, color: AppColors.darkGreen, fontSize: 15),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        email,
                        style: GoogleFonts.poppins(color: AppColors.muted, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (phone.isNotEmpty || province.isNotEmpty || role.isNotEmpty)
                        Text(
                          [if (role.isNotEmpty) role, if (province.isNotEmpty) province, if (phone.isNotEmpty) phone].join(' • '),
                          style: GoogleFonts.notoSansKhmer(color: AppColors.muted, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.edit_rounded, color: AppColors.green),
              ],
            ),
          ),
        );
      },
    );
  }
}

class AccountChip extends StatelessWidget {
  const AccountChip({super.key, required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.lightGreen,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_user_rounded, color: AppColors.green),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'គណនី: $email',
              style: GoogleFonts.notoSansKhmer(color: AppColors.darkGreen, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}


class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  String _province = kCambodianProvinces.first;
  String _role = kUserRoles.first;
  String _photoBase64 = '';
  bool _isLoading = true;
  bool _isSaving = false;

  User? get _user => FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final user = _user;
    if (user == null) return;
    await ensureUserDocument(user);
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final data = doc.data() ?? <String, dynamic>{};
    if (!mounted) return;
    setState(() {
      _nameController.text = data['name']?.toString() ?? user.displayName ?? '';
      _phoneController.text = data['phone']?.toString() ?? '';
      final province = data['province']?.toString() ?? kCambodianProvinces.first;
      final role = data['role']?.toString() ?? kUserRoles.first;
      _province = kCambodianProvinces.contains(province) ? province : kCambodianProvinces.first;
      _role = kUserRoles.contains(role) ? role : kUserRoles.first;
      _photoBase64 = data['photoBase64']?.toString() ?? '';
      _isLoading = false;
    });
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 55,
      maxWidth: 420,
      maxHeight: 420,
    );
    if (picked == null) return;
    final bytes = await File(picked.path).readAsBytes();
    setState(() => _photoBase64 = base64Encode(bytes));
  }

  Future<void> _saveProfile() async {
    final user = _user;
    if (user == null) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      showMessage(context, 'សូមបញ្ចូលឈ្មោះ');
      return;
    }
    setState(() => _isSaving = true);
    try {
      await user.updateDisplayName(name);
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'name': name,
        'email': user.email ?? '',
        'phone': _phoneController.text.trim(),
        'province': _province,
        'role': _role,
        'photoBase64': _photoBase64,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) showMessage(context, 'បានរក្សាទុក Profile រួចរាល់');
    } catch (error) {
      if (mounted) showMessage(context, 'រក្សាទុក Profile មិនបានទេ: $error');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _avatar(User user) {
    ImageProvider? imageProvider;
    if (_photoBase64.isNotEmpty) {
      try {
        imageProvider = MemoryImage(base64Decode(_photoBase64));
      } catch (_) {
        imageProvider = null;
      }
    }
    if (imageProvider == null && (user.photoURL ?? '').isNotEmpty) {
      imageProvider = NetworkImage(user.photoURL!);
    }
    return CircleAvatar(
      radius: 54,
      backgroundColor: AppColors.lightGreen,
      backgroundImage: imageProvider,
      child: imageProvider == null
          ? const Icon(Icons.person_rounded, color: AppColors.green, size: 54)
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not logged in')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('User Profile')),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.green))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: cardDecoration(),
                      child: Column(
                        children: [
                          _avatar(user),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: _pickPhoto,
                            icon: const Icon(Icons.photo_camera_back_rounded),
                            label: const Text('ប្ដូររូប Profile'),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _nameController,
                            decoration: const InputDecoration(labelText: 'ឈ្មោះពេញ'),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            enabled: false,
                            controller: TextEditingController(text: user.email ?? ''),
                            decoration: const InputDecoration(labelText: 'Email'),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(labelText: 'លេខទូរស័ព្ទ'),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: _province,
                            decoration: const InputDecoration(labelText: 'ខេត្ត / រាជធានី'),
                            items: kCambodianProvinces.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
                            onChanged: (value) => setState(() => _province = value ?? _province),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: _role,
                            decoration: const InputDecoration(labelText: 'ប្រភេទគណនី'),
                            items: kUserRoles.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
                            onChanged: (value) => setState(() => _role = value ?? _role),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _isSaving ? null : _saveProfile,
                              icon: _isSaving
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.save_rounded),
                              label: Text(_isSaving ? 'កំពុងរក្សាទុក...' : 'រក្សាទុក Profile'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () async {
                        await GoogleSignIn().signOut();
                        await FirebaseAuth.instance.signOut();
                        if (context.mounted) Navigator.pop(context);
                      },
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('ចាកចេញពីគណនី'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class AiDoctorPage extends StatefulWidget {
  const AiDoctorPage({super.key, required this.records, required this.onAddScan});

  final List<ScanRecord> records;
  final ValueChanged<ScanRecord> onAddScan;

  @override
  State<AiDoctorPage> createState() => _AiDoctorPageState();
}

class _AiDoctorPageState extends State<AiDoctorPage> {
  String _detectedCrop = 'មិនទាន់ស្គាល់';
  DiseaseResult? _result;
  File? _selectedImage;
  bool _isAnalyzing = false;
  bool _isCleaningHistory = false;
  String? _errorMessage;
  final ImagePicker _picker = ImagePicker();

  Future<void> _cleanupOldScanRecords(String userId) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('scan_records')
        .where('userId', isEqualTo: userId)
        .get();

    final docs = snapshot.docs.toList()
      ..sort((a, b) => scanRecordDateFromMap(b.data()).compareTo(scanRecordDateFromMap(a.data())));

    final oldDocs = docs.skip(20).toList();
    if (oldDocs.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in oldDocs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  void _scheduleHistoryCleanup(String userId) {
    if (_isCleaningHistory) return;
    _isCleaningHistory = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await _cleanupOldScanRecords(userId);
      } catch (_) {
        // History cleanup should never block the AI Doctor page.
      } finally {
        if (mounted) {
          setState(() => _isCleaningHistory = false);
        } else {
          _isCleaningHistory = false;
        }
      }
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final image = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1280,
      );
      if (image == null) return;

      final imageFile = File(image.path);
      setState(() {
        _selectedImage = imageFile;
        _result = null;
        _errorMessage = null;
        _detectedCrop = 'កំពុងវិភាគ...';
      });

      await _analyzeImage(imageFile);
    } catch (error) {
      setState(() => _errorMessage = 'មិនអាចជ្រើសរូបភាពបានទេ: $error');
    }
  }

  Future<void> _analyzeImage(File imageFile) async {
    setState(() {
      _isAnalyzing = true;
      _errorMessage = null;
    });

    try {
      final geminiResult = await GeminiCropDoctorService().analyzeCropImage(imageFile);
      final viewResult = geminiResult.toDiseaseResultView();
      final record = ScanRecord(
        crop: geminiResult.cropKh,
        disease: viewResult.disease,
        severity: viewResult.severity,
        confidence: viewResult.confidence,
        recommendation: viewResult.recommendation,
        createdAt: DateTime.now(),
      );

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          await FirebaseFirestore.instance.collection('scan_records').add({
            'userId': user.uid,
            'userEmail': user.email ?? '',
            'crop': record.crop,
            'disease': record.disease,
            'severity': record.severity,
            'confidence': record.confidence,
            'recommendation': record.recommendation,
            'createdAt': FieldValue.serverTimestamp(),
            'localCreatedAt': Timestamp.fromDate(record.createdAt),
          });
          await _cleanupOldScanRecords(user.uid);
        } catch (_) {
          // Keep the AI result visible even if Firestore scan history save fails.
        }
      }

      widget.onAddScan(record);
      setState(() {
        _result = DiseaseResult(
          disease: viewResult.disease,
          severity: viewResult.severity,
          confidence: viewResult.confidence,
          recommendation: viewResult.recommendation,
        );
        _detectedCrop = geminiResult.cropKh;
      });

      if (mounted) {
        showMessage(context, 'KasiAI វិភាគរូបភាពរួចរាល់');
      }
    } catch (error) {
      setState(() {
        _result = null;
        _detectedCrop = 'មិនអាចកំណត់បាន';
        _errorMessage = 'មិនអាចវិភាគដោយ AI បានទេ។ សូមពិនិត្យ Internet ហើយសាកល្បងម្ដងទៀត។\n$error';
      });
    } finally {
      if (mounted) {
        setState(() => _isAnalyzing = false);
      }
    }
  }

  Future<void> _reanalyze() async {
    final imageFile = _selectedImage;
    if (imageFile == null) {
      showMessage(context, 'សូមថតរូប ឬជ្រើសរូបភាពពី Gallery ជាមុនសិន');
      return;
    }
    await _analyzeImage(imageFile);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Crop Doctor')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageIntroCard(
                icon: Icons.camera_alt_rounded,
                title: 'ស្កេនដំណាំដោយ KasiAI',
                description: 'ថតរូប ឬជ្រើសរូបភាពពី Gallery។ AI នឹងស្គាល់ប្រភេទដំណាំ និងជំងឺដោយស្វ័យប្រវត្តិ។',
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: cardDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.lightGreen,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.cloud_done_rounded, color: AppColors.green),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Auto mode: Camera/Gallery → KasiAI → លទ្ធផលជាភាសាខ្មែរ។ មិនចាំបាច់ជ្រើសប្រភេទដំណាំ។',
                              style: GoogleFonts.notoSansKhmer(color: AppColors.darkGreen, height: 1.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _ImagePickerPanel(
                      imageFile: _selectedImage,
                      onCamera: () => _pickImage(ImageSource.camera),
                      onGallery: () => _pickImage(ImageSource.gallery),
                    ),
                    const SizedBox(height: 16),
                    if (_isAnalyzing)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.lightGreen,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.green),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'KasiAI កំពុងស្គាល់ដំណាំ និងជំងឺ...',
                                style: GoogleFonts.notoSansKhmer(color: AppColors.darkGreen, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (_selectedImage != null)
                      FilledButton.icon(
                        onPressed: _reanalyze,
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('វិភាគម្ដងទៀតដោយ KasiAI'),
                      ),
                  ],
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFFFCDD2)),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: GoogleFonts.notoSansKhmer(color: AppColors.danger, height: 1.5),
                  ),
                ),
              ],
              if (_result != null) ...[
                const SizedBox(height: 18),
                ResultCard(crop: _detectedCrop, result: _result!),
              ],
              const SizedBox(height: 22),
              SectionTitle(title: 'ប្រវត្តិ AI Scan'),
              const SizedBox(height: 10),
              _ScanHistoryList(
                fallbackRecords: widget.records,
                onTooManyRecords: _scheduleHistoryCleanup,
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _ScanHistoryList extends StatelessWidget {
  const _ScanHistoryList({required this.fallbackRecords, required this.onTooManyRecords});

  final List<ScanRecord> fallbackRecords;
  final ValueChanged<String> onTooManyRecords;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      final records = fallbackRecords.take(20).toList();
      if (records.isEmpty) return const EmptyState(text: 'មិនទាន់មានប្រវត្តិស្កេនទេ');
      return PagedList<ScanRecord>(
        items: records,
        pageSize: 10,
        itemBuilder: (context, record) => ScanHistoryCard(record: record),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('scan_records')
          .where('userId', isEqualTo: user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: cardDecoration(),
            child: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.green),
                ),
                const SizedBox(width: 12),
                Text('កំពុងទាញប្រវត្តិ...', style: GoogleFonts.notoSansKhmer(color: AppColors.darkGreen)),
              ],
            ),
          );
        }

        final docs = snapshot.data?.docs.toList() ?? [];
        docs.sort((a, b) => scanRecordDateFromMap(b.data()).compareTo(scanRecordDateFromMap(a.data())));

        if (docs.length > 20) {
          onTooManyRecords(user.uid);
        }

        final cloudRecords = docs.take(20).map(scanRecordFromFirestore).toList();
        final records = cloudRecords.isNotEmpty ? cloudRecords : fallbackRecords.take(20).toList();

        if (records.isEmpty) return const EmptyState(text: 'មិនទាន់មានប្រវត្តិស្កេនទេ');

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.lightGreen,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                'បង្ហាញ 10 កំណត់ត្រា ក្នុងមួយទំព័រ។ ប្រព័ន្ធរក្សាទុកតែ 20 ប្រវត្តិចុងក្រោយប៉ុណ្ណោះ។',
                style: GoogleFonts.notoSansKhmer(color: AppColors.darkGreen, height: 1.5),
              ),
            ),
            PagedList<ScanRecord>(
              items: records,
              pageSize: 10,
              itemBuilder: (context, record) => ScanHistoryCard(record: record),
            ),
          ],
        );
      },
    );
  }
}

class _ImagePickerPanel extends StatelessWidget {
  const _ImagePickerPanel({required this.imageFile, required this.onCamera, required this.onGallery});

  final File? imageFile;
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.lightGreen,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          if (imageFile == null)
            Column(
              children: [
                const Icon(Icons.add_a_photo, color: AppColors.green, size: 42),
                const SizedBox(height: 8),
                Text(
                  'ជ្រើសរូបភាពស្លឹក ឬផ្លែដំណាំ',
                  style: GoogleFonts.notoSansKhmer(fontWeight: FontWeight.bold),
                ),
              ],
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(
                imageFile!,
                height: 190,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onCamera,
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('Camera'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onGallery,
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Gallery'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


class PlantingPage extends StatefulWidget {
  const PlantingPage({
    super.key,
    required this.records,
    required this.onAddRecord,
    required this.generateId,
  });

  final List<PlantingRecord> records;
  final ValueChanged<PlantingRecord> onAddRecord;
  final int Function() generateId;

  @override
  State<PlantingPage> createState() => _PlantingPageState();
}

class _PlantingPageState extends State<PlantingPage> {
  String _crop = 'ម្ទេស';
  String _province = 'កំពង់ចាម';
  DateTime _harvestDate = DateTime(2026, 7, 15);
  bool _isSaving = false;
  bool _isPredictingSupply = false;
  SupplyAiPrediction? _aiPrediction;
  String? _predictionError;
  final SupplyPredictorService _supplyPredictorService = SupplyPredictorService();
  final TextEditingController _areaController = TextEditingController(text: '1');
  final TextEditingController _expectedController = TextEditingController(text: '1200');

  final List<String> _crops = kCambodianCrops;
  final List<String> _provinces = kCambodianProvinces;

  @override
  void dispose() {
    _areaController.dispose();
    _expectedController.dispose();
    super.dispose();
  }

  CollectionReference<Map<String, dynamic>> get _plantingCollection =>
      FirebaseFirestore.instance.collection('planting_records');

  Future<void> _addRecord() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      showMessage(context, 'សូមចូលគណនីជាមុនសិន');
      return;
    }

    final area = double.tryParse(_areaController.text.trim()) ?? 0;
    final expected = double.tryParse(_expectedController.text.trim()) ?? 0;

    if (area <= 0 || expected <= 0) {
      showMessage(context, 'សូមបញ្ចូលផ្ទៃដី និងទិន្នផលរំពឹងទុកឱ្យត្រឹមត្រូវ');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final record = PlantingRecord(
        id: widget.generateId(),
        crop: _crop,
        province: _province,
        area: area,
        expectedKg: expected,
        harvestDate: _harvestDate,
        userId: user.uid,
      );

      await _plantingCollection.add({
        'userId': user.uid,
        'userEmail': user.email ?? '',
        'crop': _crop,
        'province': _province,
        'areaHa': area,
        'expectedKg': expected,
        'harvestDate': Timestamp.fromDate(_harvestDate),
        'harvestYear': _harvestDate.year,
        'harvestMonth': _harvestDate.month,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      widget.onAddRecord(record);
      if (mounted) {
        showMessage(context, 'បានរក្សាទុកទៅ Firestore និងទស្សន៍ទាយរួចរាល់');
      }
      await _runAiSupplyPrediction(silent: true);
    } catch (error) {
      if (mounted) {
        showMessage(context, 'រក្សាទុកមិនបានទេ: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _runAiSupplyPrediction({bool silent = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    setState(() {
      _isPredictingSupply = true;
      _predictionError = null;
    });

    try {
      final prediction = await _supplyPredictorService.predict(
        crop: _crop,
        province: _province,
        harvestYear: _harvestDate.year,
        harvestMonth: _harvestDate.month,
        userId: user?.uid ?? '',
      );

      if (!mounted) return;
      setState(() => _aiPrediction = prediction);
      if (!silent) {
        showMessage(context, 'AI បានទស្សន៍ទាយការផ្គត់ផ្គង់ពីទិន្នន័យ Firestore រួចរាល់');
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _predictionError = error.toString());
      if (!silent) {
        showMessage(context, 'AI Supply Predictor មិនដំណើរការ: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _isPredictingSupply = false);
      }
    }
  }

  Future<void> _pickHarvestDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _harvestDate,
      firstDate: DateTime(2026, 1, 1),
      lastDate: DateTime(2028, 12, 31),
    );
    if (picked != null) {
      setState(() => _harvestDate = picked);
    }
  }

  List<PlantingRecord> _recordsFromSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    return snapshot.docs.map(PlantingRecord.fromFirestore).toList();
  }

  List<ForecastSummary> _forecastSummaries(List<PlantingRecord> records) {
    final Map<String, ForecastSummary> summaries = {};
    for (final record in records) {
      final key = '${record.crop}|${record.province}|${record.harvestDate.year}|${record.harvestDate.month}';
      final existing = summaries[key];
      if (existing == null) {
        summaries[key] = ForecastSummary(
          crop: record.crop,
          province: record.province,
          harvestYear: record.harvestDate.year,
          harvestMonth: record.harvestDate.month,
          expectedKg: record.expectedKg,
          recordCount: 1,
        );
      } else {
        summaries[key] = existing.copyWith(
          expectedKg: existing.expectedKg + record.expectedKg,
          recordCount: existing.recordCount + 1,
        );
      }
    }
    final list = summaries.values.toList()
      ..sort((a, b) => b.expectedKg.compareTo(a.expectedKg));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Crop Supply Predictor')),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _plantingCollection.orderBy('createdAt', descending: true).snapshots(),
          builder: (context, snapshot) {
            final hasFirestoreData = snapshot.hasData && snapshot.data!.docs.isNotEmpty;
            final allRecords = snapshot.hasData ? _recordsFromSnapshot(snapshot.data!) : <PlantingRecord>[];
            final recordsForForecast = hasFirestoreData ? allRecords : widget.records;
            final myRecords = allRecords.where((record) => record.userId == currentUserId).toList();
            final recordsForList = hasFirestoreData ? myRecords : widget.records;
            final forecasts = _forecastSummaries(recordsForForecast);

            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PageIntroCard(
                    icon: Icons.insights_rounded,
                    title: 'ទស្សន៍ទាយការផ្គត់ផ្គង់',
                    description: 'ទិន្នន័យត្រូវបានរក្សាទុកតាមគណនី និងគណនាការផ្គត់ផ្គង់សរុបពី Firestore។',
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: cardDecoration(),
                    child: Column(
                      children: [
                        DropdownButtonFormField<String>(
                          value: _crop,
                          decoration: const InputDecoration(labelText: 'ដំណាំ'),
                          items: _crops.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
                          onChanged: (value) => setState(() => _crop = value ?? _crop),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: _province,
                          decoration: const InputDecoration(labelText: 'ខេត្ត'),
                          items: _provinces.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
                          onChanged: (value) => setState(() => _province = value ?? _province),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _areaController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'ផ្ទៃដី (ha)'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _expectedController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'ទិន្នផល (kg)'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _pickHarvestDate,
                          icon: const Icon(Icons.calendar_month),
                          label: Text('ថ្ងៃប្រមូលផល: ${formatDate(_harvestDate)}'),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _isSaving ? null : _addRecord,
                          icon: _isSaving
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.cloud_upload_rounded),
                          label: Text(_isSaving ? 'កំពុងរក្សាទុក...' : 'រក្សាទុក និងទស្សន៍ទាយ'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _isPredictingSupply ? null : () => _runAiSupplyPrediction(),
                          icon: _isPredictingSupply
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.green))
                              : const Icon(Icons.auto_awesome_rounded),
                          label: Text(_isPredictingSupply ? 'AI កំពុងវិភាគ...' : 'ទស្សន៍ទាយដោយ Cloud AI'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  SectionTitle(title: 'Supply Forecast'),
                  const SizedBox(height: 10),
                  if (_aiPrediction != null) ...[
                    AiSupplyPredictionCard(prediction: _aiPrediction!),
                    const SizedBox(height: 12),
                  ] else if (_predictionError != null) ...[
                    CloudErrorCard(message: _predictionError!),
                    const SizedBox(height: 12),
                  ],
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const Center(child: Padding(padding: EdgeInsets.all(18), child: CircularProgressIndicator(color: AppColors.green)))
                  else if (forecasts.isEmpty)
                    const EmptyState(text: 'មិនទាន់មានទិន្នន័យដាំដុះនៅ Firestore ទេ')
                  else
                    ...forecasts.map((forecast) => ForecastCard(summary: forecast)),
                  const SizedBox(height: 22),
                  SectionTitle(title: 'កំណត់ត្រាដាំដុះរបស់ខ្ញុំ'),
                  const SizedBox(height: 10),
                  if (recordsForList.isEmpty)
                    const EmptyState(text: 'អ្នកមិនទាន់មានកំណត់ត្រាដាំដុះទេ')
                  else
                    ...recordsForList.map((record) => PlantingRecordCard(record: record)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class ForecastSummary {
  const ForecastSummary({
    required this.crop,
    required this.province,
    required this.harvestYear,
    required this.harvestMonth,
    required this.expectedKg,
    required this.recordCount,
  });

  final String crop;
  final String province;
  final int harvestYear;
  final int harvestMonth;
  final double expectedKg;
  final int recordCount;

  ForecastSummary copyWith({double? expectedKg, int? recordCount}) {
    return ForecastSummary(
      crop: crop,
      province: province,
      harvestYear: harvestYear,
      harvestMonth: harvestMonth,
      expectedKg: expectedKg ?? this.expectedKg,
      recordCount: recordCount ?? this.recordCount,
    );
  }
}

class MarketplacePage extends StatelessWidget {
  const MarketplacePage({
    super.key,
    required this.products,
    required this.demands,
    required this.deals,
    required this.onAddProduct,
    required this.onAddDemand,
    required this.onCreateDealFromProduct,
    required this.onCreateDealFromDemand,
    required this.generateId,
  });

  final List<ProductListing> products;
  final List<BuyingDemand> demands;
  final List<DealRecord> deals;
  final ValueChanged<ProductListing> onAddProduct;
  final ValueChanged<BuyingDemand> onAddDemand;
  final ValueChanged<ProductListing> onCreateDealFromProduct;
  final ValueChanged<BuyingDemand> onCreateDealFromDemand;
  final int Function() generateId;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Smart Marketplace'),
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Color(0xFFE8F5E9),
            indicatorColor: AppColors.amber,
            tabs: [
              Tab(text: 'ផលិតផល'),
              Tab(text: 'តម្រូវការ'),
              Tab(text: 'Deals'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            ProductTab(),
            DemandTab(),
            DealTab(),
          ],
        ),
      ),
    );
  }
}



class ProductTab extends StatelessWidget {
  const ProductTab({super.key});

  CollectionReference<Map<String, dynamic>> get _collection => FirebaseFirestore.instance.collection('product_listings');

  Future<void> _showAddProductDialog(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      showMessage(context, 'សូមចូលគណនីជាមុនសិន');
      return;
    }

    final result = await showProductListingEditorDialog(context);
    if (result == null) return;

    final profile = await currentUserMarketplaceProfile(user);
    final data = result.toFirestore();
    data.addAll({
      'userId': user.uid,
      'userEmail': profile['email'],
      'farmerId': user.uid,
      'farmerName': profile['name'],
      'farmerEmail': profile['email'],
      'farmerPhone': profile['phone'],
      'farmerProvince': profile['province'],
      'farmerRole': profile['role'],
      'farmerPhotoBase64': profile['photoBase64'],
      'farmerPhotoUrl': profile['photoUrl'],
      'active': true,
      'status': 'Active',
    });
    await _collection.add(data);
    if (context.mounted) showMessage(context, 'បានបង្ហោះផលិតផលទៅទីផ្សារ');
  }

  Future<void> _showEditProductDialog(BuildContext context, ProductListing product) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || product.userId != user.uid || product.documentId == null) {
      showMessage(context, 'អ្នកអាចកែតែ Post របស់ខ្លួនប៉ុណ្ណោះ');
      return;
    }

    final result = await showProductListingEditorDialog(context, existing: product);
    if (result == null) return;

    final data = result.toFirestore();
    data.remove('createdAt');
    data.addAll({
      'updatedAt': FieldValue.serverTimestamp(),
      'active': true,
      'status': product.status == 'Completed' ? 'Active' : product.status,
    });
    await _collection.doc(product.documentId).set(data, SetOptions(merge: true));
    if (context.mounted) showMessage(context, 'បានកែប្រែផលិតផល');
  }

  Future<void> _deleteProduct(BuildContext context, ProductListing product) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || product.userId != user.uid || product.documentId == null) {
      showMessage(context, 'អ្នកអាចលុបតែ Post របស់ខ្លួនប៉ុណ្ណោះ');
      return;
    }
    final confirmed = await showConfirmDialog(context, 'លុបផលិតផលនេះ?', 'Post នឹងត្រូវលុបចេញពី Smart Marketplace។');
    if (!confirmed) return;
    await _collection.doc(product.documentId).delete();
    if (context.mounted) showMessage(context, 'បានលុបផលិតផល');
  }

  Future<void> _createDealFromProduct(BuildContext context, ProductListing product) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      showMessage(context, 'សូមចូលគណនីជាមុនសិន');
      return;
    }
    if (product.userId == user.uid) {
      showMessage(context, 'អ្នកមិនអាច Request Deal លើផលិតផលខ្លួនឯងបានទេ');
      return;
    }
    if (!product.isVisibleInMarket) {
      showMessage(context, 'ផលិតផលនេះមិនមាននៅទីផ្សារទៀតទេ');
      return;
    }

    final request = await showDealRequestDialog(
      context,
      title: 'Request Deal: ${product.crop}',
      maxQuantity: product.quantity,
      price: product.price,
    );
    if (request == null) return;

    final buyerProfile = await currentUserMarketplaceProfile(user);
    final value = request.quantity * product.price;
    final dealRef = await FirebaseFirestore.instance.collection('deals').add({
      'type': 'product_request',
      'productId': product.documentId ?? '',
      'crop': product.crop,
      'province': product.province,
      'buyerId': user.uid,
      'buyerName': buyerProfile['name'],
      'buyerEmail': buyerProfile['email'],
      'buyerPhone': buyerProfile['phone'],
      'buyerProvince': buyerProfile['province'],
      'buyerRole': buyerProfile['role'],
      'buyerPhotoBase64': buyerProfile['photoBase64'],
      'buyerPhotoUrl': buyerProfile['photoUrl'],
      'farmerId': product.userId,
      'farmerName': product.farmerName,
      'farmerEmail': product.userEmail,
      'farmerPhone': product.farmerPhone,
      'farmerProvince': product.farmerProvince,
      'farmerRole': product.farmerRole,
      'farmerPhotoBase64': product.farmerPhotoBase64,
      'farmerPhotoUrl': product.farmerPhotoUrl,
      'productPhotoBase64': product.photoBase64,
      'quantity': request.quantity,
      'price': product.price,
      'value': value,
      'commission': value * 0.02,
      'status': 'Requested',
      'note': request.note,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await createMarketplaceNotification(
      toUserId: product.userId,
      title: 'មានអ្នក Request Deal',
      message: '${buyerProfile['name']} ចង់ទិញ ${product.crop} ${request.quantity.toStringAsFixed(0)}kg',
      type: 'deal_request',
      referenceCollection: 'deals',
      referenceId: dealRef.id,
    );
    if (context.mounted) showMessage(context, 'បានផ្ញើ Request Deal ទៅអ្នកលក់');
  }

  @override
  Widget build(BuildContext context) {
    return ListWithAction(
      buttonLabel: 'បង្ហោះផលិតផលថ្មី',
      onPressed: () => _showAddProductDialog(context),
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _collection.orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: Padding(padding: EdgeInsets.all(18), child: CircularProgressIndicator(color: AppColors.green)));
          }
          final products = snapshot.hasData
              ? snapshot.data!.docs.map(ProductListing.fromFirestore).where((product) => product.isVisibleInMarket).toList()
              : <ProductListing>[];
          if (products.isEmpty) return const EmptyState(text: 'មិនទាន់មានផលិតផលនៅ Firestore ទេ');
          return PagedList<ProductListing>(
            items: products,
            pageSize: 10,
            itemBuilder: (context, product) => ProductCard(
              product: product,
              onDeal: () => _createDealFromProduct(context, product),
              onEdit: () => _showEditProductDialog(context, product),
              onDelete: () => _deleteProduct(context, product),
            ),
          );
        },
      ),
    );
  }
}

class DemandTab extends StatelessWidget {
  const DemandTab({super.key});

  CollectionReference<Map<String, dynamic>> get _demandCollection => FirebaseFirestore.instance.collection('buying_demands');
  CollectionReference<Map<String, dynamic>> get _productCollection => FirebaseFirestore.instance.collection('product_listings');

  Future<void> _showAddDemandDialog(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      showMessage(context, 'សូមចូលគណនីជាមុនសិន');
      return;
    }

    final result = await showBuyingDemandEditorDialog(context);
    if (result == null) return;

    final profile = await currentUserMarketplaceProfile(user);
    final data = result.toFirestore();
    data.addAll({
      'userId': user.uid,
      'userEmail': profile['email'],
      'buyerId': user.uid,
      'buyerName': profile['name'],
      'buyerEmail': profile['email'],
      'buyerPhone': profile['phone'],
      'buyerProvince': profile['province'],
      'buyerRole': profile['role'],
      'buyerPhotoBase64': profile['photoBase64'],
      'buyerPhotoUrl': profile['photoUrl'],
      'active': true,
      'status': 'Active',
    });
    await _demandCollection.add(data);
    if (context.mounted) showMessage(context, 'បានបន្ថែមតម្រូវការទិញ');
  }

  Future<void> _showEditDemandDialog(BuildContext context, BuyingDemand demand) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || demand.userId != user.uid || demand.documentId == null) {
      showMessage(context, 'អ្នកអាចកែតែ Post របស់ខ្លួនប៉ុណ្ណោះ');
      return;
    }

    final result = await showBuyingDemandEditorDialog(context, existing: demand);
    if (result == null) return;

    final data = result.toFirestore();
    data.remove('createdAt');
    data.addAll({
      'updatedAt': FieldValue.serverTimestamp(),
      'active': true,
      'status': demand.status == 'Completed' ? 'Active' : demand.status,
    });
    await _demandCollection.doc(demand.documentId).set(data, SetOptions(merge: true));
    if (context.mounted) showMessage(context, 'បានកែប្រែតម្រូវការ');
  }

  Future<void> _deleteDemand(BuildContext context, BuyingDemand demand) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || demand.userId != user.uid || demand.documentId == null) {
      showMessage(context, 'អ្នកអាចលុបតែ Post របស់ខ្លួនប៉ុណ្ណោះ');
      return;
    }
    final confirmed = await showConfirmDialog(context, 'លុបតម្រូវការនេះ?', 'Post នឹងត្រូវលុបចេញពី Smart Marketplace។');
    if (!confirmed) return;
    await _demandCollection.doc(demand.documentId).delete();
    if (context.mounted) showMessage(context, 'បានលុបតម្រូវការ');
  }

  Future<void> _createDealFromDemand(BuildContext context, BuyingDemand demand) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      showMessage(context, 'សូមចូលគណនីជាមុនសិន');
      return;
    }
    if (demand.userId == user.uid) {
      showMessage(context, 'អ្នកមិនអាច Match Deal លើតម្រូវការខ្លួនឯងបានទេ');
      return;
    }
    if (!demand.isVisibleInMarket) {
      showMessage(context, 'តម្រូវការនេះមិនមាននៅទីផ្សារទៀតទេ');
      return;
    }

    final request = await showDealRequestDialog(
      context,
      title: 'Match Deal: ${demand.crop}',
      maxQuantity: demand.quantity,
      price: demand.targetPrice,
    );
    if (request == null) return;

    final farmerProfile = await currentUserMarketplaceProfile(user);
    final value = request.quantity * demand.targetPrice;
    final dealRef = await FirebaseFirestore.instance.collection('deals').add({
      'type': 'demand_match',
      'demandId': demand.documentId ?? '',
      'crop': demand.crop,
      'province': demand.province,
      'buyerId': demand.userId,
      'buyerName': demand.buyerName,
      'buyerEmail': demand.userEmail,
      'buyerPhone': demand.buyerPhone,
      'buyerProvince': demand.buyerProvince,
      'buyerRole': demand.buyerRole,
      'buyerPhotoBase64': demand.buyerPhotoBase64,
      'buyerPhotoUrl': demand.buyerPhotoUrl,
      'farmerId': user.uid,
      'farmerName': farmerProfile['name'],
      'farmerEmail': farmerProfile['email'],
      'farmerPhone': farmerProfile['phone'],
      'farmerProvince': farmerProfile['province'],
      'farmerRole': farmerProfile['role'],
      'farmerPhotoBase64': farmerProfile['photoBase64'],
      'farmerPhotoUrl': farmerProfile['photoUrl'],
      'quantity': request.quantity,
      'price': demand.targetPrice,
      'value': value,
      'commission': value * 0.02,
      'status': 'Matched',
      'note': request.note,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await createMarketplaceNotification(
      toUserId: demand.userId,
      title: 'មានអ្នក Match Deal',
      message: '${farmerProfile['name']} អាចផ្គត់ផ្គង់ ${demand.crop} ${request.quantity.toStringAsFixed(0)}kg',
      type: 'deal_match',
      referenceCollection: 'deals',
      referenceId: dealRef.id,
    );
    if (context.mounted) showMessage(context, 'បានបង្កើត Match Deal ជាមួយអ្នកទិញ');
  }

  @override
  Widget build(BuildContext context) {
    return ListWithAction(
      buttonLabel: 'បង្ហោះតម្រូវការថ្មី',
      onPressed: () => _showAddDemandDialog(context),
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _productCollection.snapshots(),
        builder: (context, productSnapshot) {
          final products = productSnapshot.hasData
              ? productSnapshot.data!.docs.map(ProductListing.fromFirestore).where((product) => product.isVisibleInMarket).toList()
              : <ProductListing>[];
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _demandCollection.orderBy('createdAt', descending: true).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: Padding(padding: EdgeInsets.all(18), child: CircularProgressIndicator(color: AppColors.green)));
              }
              final demands = snapshot.hasData
                  ? snapshot.data!.docs.map(BuyingDemand.fromFirestore).where((demand) => demand.isVisibleInMarket).toList()
                  : <BuyingDemand>[];
              if (demands.isEmpty) return const EmptyState(text: 'មិនទាន់មានតម្រូវការទិញនៅ Firestore ទេ');
              return PagedList<BuyingDemand>(
                items: demands,
                pageSize: 10,
                itemBuilder: (context, demand) {
                  final matchCount = products.where((p) => p.crop == demand.crop && p.quantity > 0).length;
                  return DemandCard(
                    demand: demand,
                    matchCount: matchCount,
                    onDeal: () => _createDealFromDemand(context, demand),
                    onEdit: () => _showEditDemandDialog(context, demand),
                    onDelete: () => _deleteDemand(context, demand),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class DealTab extends StatelessWidget {
  const DealTab({super.key});

  CollectionReference<Map<String, dynamic>> get _collection => FirebaseFirestore.instance.collection('deals');

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _collection.orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: Padding(padding: EdgeInsets.all(18), child: CircularProgressIndicator(color: AppColors.green)));
          }
          final allDeals = snapshot.hasData ? snapshot.data!.docs.map(DealRecord.fromFirestore).toList() : <DealRecord>[];
          final deals = user == null
              ? <DealRecord>[]
              : allDeals.where((deal) => deal.buyerId == user.uid || deal.farmerId == user.uid).toList();
          if (deals.isEmpty) return const EmptyState(text: 'មិនទាន់មាន Deal សម្រាប់គណនីនេះទេ។ សូមចុច Request Deal ឬ Match Deal។');
          return PagedList<DealRecord>(
            items: deals,
            pageSize: 10,
            itemBuilder: (context, deal) => DealCard(deal: deal),
          );
        },
      ),
    );
  }
}

class UserDashboardStats extends StatelessWidget {
  const UserDashboardStats({super.key, required this.localScanCount});

  final int localScanCount;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('scan_records')
          .where('userId', isEqualTo: user.uid)
          .snapshots(),
      builder: (context, scanSnapshot) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('product_listings')
              .where('userId', isEqualTo: user.uid)
              .snapshots(),
          builder: (context, productSnapshot) {
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('buying_demands')
                  .where('userId', isEqualTo: user.uid)
                  .snapshots(),
              builder: (context, demandSnapshot) {
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance.collection('deals').snapshots(),
                  builder: (context, dealSnapshot) {
                    final scanCount = (scanSnapshot.data?.docs.length ?? 0) > 0 ? scanSnapshot.data!.docs.length : localScanCount;
                    final productCount = productSnapshot.data?.docs.length ?? 0;
                    final demandCount = demandSnapshot.data?.docs.length ?? 0;
                    final myDeals = (dealSnapshot.data?.docs ?? []).where((doc) {
                      final data = doc.data();
                      return data['buyerId'] == user.uid || data['farmerId'] == user.uid;
                    }).toList();
                    final revenue = myDeals.fold<double>(0, (sum, doc) {
                      final value = doc.data()['commission'];
                      if (value is num) return sum + value.toDouble();
                      return sum + (double.tryParse(value?.toString() ?? '') ?? 0);
                    });

                    return Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: StatCard(title: 'My Scans', value: '$scanCount', icon: Icons.camera_alt)),
                            const SizedBox(width: 12),
                            Expanded(child: StatCard(title: 'My Products', value: '$productCount', icon: Icons.eco)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: StatCard(title: 'My Demands', value: '$demandCount', icon: Icons.shopping_bag)),
                            const SizedBox(width: 12),
                            Expanded(child: StatCard(title: 'My Commission', value: money(revenue), icon: Icons.attach_money)),
                          ],
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.scans,
    required this.plantings,
    required this.products,
    required this.demands,
    required this.deals,
    required this.profitRecords,
    required this.onAddProfit,
  });

  final List<ScanRecord> scans;
  final List<PlantingRecord> plantings;
  final List<ProductListing> products;
  final List<BuyingDemand> demands;
  final List<DealRecord> deals;
  final List<ProfitRecord> profitRecords;
  final ValueChanged<ProfitRecord> onAddProfit;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final TextEditingController _titleController = TextEditingController(text: 'ថ្លៃដឹកជញ្ជូន');
  final TextEditingController _amountController = TextEditingController(text: '25');
  ProfitType _type = ProfitType.expense;
  bool _isSavingProfit = false;

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<void> _addProfitRecord() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      showMessage(context, 'សូមចូលគណនីជាមុនសិន');
      return;
    }

    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    final title = _titleController.text.trim();
    if (title.isEmpty || amount <= 0) {
      showMessage(context, 'សូមបញ្ចូលទិន្នន័យឱ្យបានត្រឹមត្រូវ');
      return;
    }

    setState(() => _isSavingProfit = true);
    try {
      await FirebaseFirestore.instance.collection('profit_records').add({
        'userId': user.uid,
        'userEmail': user.email ?? '',
        'title': title,
        'type': _type == ProfitType.income ? 'income' : 'expense',
        'amount': amount,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _amountController.clear();
      showMessage(context, 'បានរក្សាទុកកំណត់ត្រាចំណូល/ចំណាយទៅ Firestore');
    } catch (error) {
      showMessage(context, 'រក្សាទុកមិនបានទេ: $error');
    } finally {
      if (mounted) setState(() => _isSavingProfit = false);
    }
  }

  List<ProfitRecord> _profitRecordsFromSnapshot(QuerySnapshot<Map<String, dynamic>>? snapshot) {
    final docs = snapshot?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final sortedDocs = [...docs];
    sortedDocs.sort((a, b) {
      final aTime = a.data()['createdAt'];
      final bTime = b.data()['createdAt'];
      final aDate = aTime is Timestamp ? aTime.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = bTime is Timestamp ? bTime.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });

    return sortedDocs.map((doc) {
      final data = doc.data();
      final typeText = data['type']?.toString() ?? 'expense';
      return ProfitRecord(
        title: data['title']?.toString() ?? 'កំណត់ត្រា',
        type: typeText == 'income' ? ProfitType.income : ProfitType.expense,
        amount: _toDouble(data['amount']),
      );
    }).toList();
  }

  List<MarketPrice> _buildMarketPrices({
    required QuerySnapshot<Map<String, dynamic>>? productSnapshot,
    required QuerySnapshot<Map<String, dynamic>>? demandSnapshot,
  }) {
    final Map<String, List<double>> priceMap = {};
    final Map<String, double> quantityMap = {};

    void addPrice(String crop, double price, double quantity) {
      if (crop.trim().isEmpty || price <= 0) return;
      priceMap.putIfAbsent(crop, () => <double>[]).add(price);
      quantityMap[crop] = (quantityMap[crop] ?? 0) + (quantity > 0 ? quantity : 0);
    }

    for (final doc in productSnapshot?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
      final data = doc.data();
      addPrice(
        data['crop']?.toString() ?? '',
        _toDouble(data['price']),
        _toDouble(data['quantity']),
      );
    }

    for (final doc in demandSnapshot?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
      final data = doc.data();
      addPrice(
        data['crop']?.toString() ?? '',
        _toDouble(data['targetPrice'] ?? data['price']),
        _toDouble(data['quantity']),
      );
    }

    final prices = priceMap.entries.map((entry) {
      final crop = entry.key;
      final values = entry.value;
      final avg = values.fold<double>(0, (sum, value) => sum + value) / values.length;
      final qty = quantityMap[crop] ?? 0;
      return MarketPrice(
        crop: crop,
        price: avg,
        trend: 'Firestore • ${values.length} price records • ${qty.toStringAsFixed(0)} kg',
      );
    }).toList();

    prices.sort((a, b) => a.crop.compareTo(b.crop));
    return prices;
  }

  Widget _marketPriceBoard() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('product_listings').snapshots(),
      builder: (context, productSnapshot) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('buying_demands').snapshots(),
          builder: (context, demandSnapshot) {
            if (productSnapshot.connectionState == ConnectionState.waiting || demandSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: Padding(padding: EdgeInsets.all(18), child: CircularProgressIndicator(color: AppColors.green)));
            }

            final prices = _buildMarketPrices(
              productSnapshot: productSnapshot.data,
              demandSnapshot: demandSnapshot.data,
            );

            if (prices.isEmpty) {
              return const EmptyState(text: 'មិនទាន់មានតម្លៃទីផ្សារពិតទេ។ សូមបង្ហោះផលិតផល ឬតម្រូវការទិញនៅ Smart Marketplace សិន។');
            }

            return Column(children: prices.map((price) => PriceCard(price: price)).toList());
          },
        );
      },
    );
  }

  Widget _profitRecordSection() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const EmptyState(text: 'សូមចូលគណនីជាមុនសិន');

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('profit_records')
          .where('userId', isEqualTo: user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        final records = _profitRecordsFromSnapshot(snapshot.data);
        final totalIncome = records.where((item) => item.type == ProfitType.income).fold<double>(0, (sum, item) => sum + item.amount);
        final totalExpense = records.where((item) => item.type == ProfitType.expense).fold<double>(0, (sum, item) => sum + item.amount);
        final profit = totalIncome - totalExpense;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: cardDecoration(),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: SummaryBox(label: 'ចំណូល', value: money(totalIncome), color: AppColors.green)),
                      const SizedBox(width: 10),
                      Expanded(child: SummaryBox(label: 'ចំណាយ', value: money(totalExpense), color: AppColors.danger)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SummaryBox(label: 'ចំណេញ/ខាត', value: money(profit), color: profit >= 0 ? AppColors.darkGreen : AppColors.danger),
                  const SizedBox(height: 16),
                  TextField(controller: _titleController, decoration: const InputDecoration(labelText: 'ចំណងជើង')),
                  const SizedBox(height: 10),
                  TextField(controller: _amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'ចំនួនទឹកប្រាក់ \$')),
                  const SizedBox(height: 10),
                  SegmentedButton<ProfitType>(
                    segments: const [
                      ButtonSegment(value: ProfitType.expense, label: Text('ចំណាយ')),
                      ButtonSegment(value: ProfitType.income, label: Text('ចំណូល')),
                    ],
                    selected: {_type},
                    onSelectionChanged: (value) => setState(() => _type = value.first),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _isSavingProfit ? null : _addProfitRecord,
                    icon: _isSavingProfit
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save),
                    label: Text(_isSavingProfit ? 'កំពុងរក្សាទុក...' : 'បន្ថែមកំណត់ត្រា'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (snapshot.connectionState == ConnectionState.waiting)
              const Center(child: Padding(padding: EdgeInsets.all(18), child: CircularProgressIndicator(color: AppColors.green)))
            else if (records.isEmpty)
              const EmptyState(text: 'មិនទាន់មានកំណត់ត្រាចំណូល/ចំណាយនៅ Firestore ទេ')
            else
              ...records.map((record) => ProfitRecordCard(record: record)),
          ],
        );
      },
    );
  }

  Widget _businessSummary() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('deals').snapshots(),
      builder: (context, dealSnapshot) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('planting_records')
              .where('userId', isEqualTo: user.uid)
              .snapshots(),
          builder: (context, plantingSnapshot) {
            final dealDocs = (dealSnapshot.data?.docs ?? []).where((doc) {
              final data = doc.data();
              return data['buyerId'] == user.uid || data['farmerId'] == user.uid;
            }).toList();

            final totalDealValue = dealDocs.fold<double>(0, (sum, doc) => sum + _toDouble(doc.data()['value']));
            final totalCommission = dealDocs.fold<double>(0, (sum, doc) => sum + _toDouble(doc.data()['commission']));
            final plantingCount = plantingSnapshot.data?.docs.length ?? 0;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InfoLine(label: 'Deal value សរុប', value: money(totalDealValue)),
                InfoLine(label: 'Commission 2%', value: money(totalCommission)),
                InfoLine(label: 'Planting records', value: '$plantingCount records'),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              UserDashboardStats(localScanCount: widget.scans.length),
              const SizedBox(height: 22),
              SectionTitle(title: 'Market Price Board'),
              const SizedBox(height: 10),
              _marketPriceBoard(),
              const SizedBox(height: 22),
              SectionTitle(title: 'Farmer Profit Record'),
              const SizedBox(height: 10),
              _profitRecordSection(),
              const SizedBox(height: 22),
              SectionTitle(title: 'Business Summary'),
              const SizedBox(height: 10),
              _businessSummary(),
            ],
          ),
        ),
      ),
    );
  }
}


class FeatureCard extends StatelessWidget {
  const FeatureCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(18),
        decoration: cardDecoration(),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconBox(icon: icon),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.darkGreen),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: GoogleFonts.notoSansKhmer(fontSize: 14, height: 1.55, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.green),
          ],
        ),
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.title, required this.value, required this.icon});

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.green),
          const SizedBox(height: 8),
          Text(value, style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.darkGreen)),
          Text(title, style: GoogleFonts.notoSansKhmer(fontSize: 12, color: AppColors.muted)),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.moul(fontSize: 19, color: AppColors.darkGreen),
          ),
        ),
        if (actionLabel != null)
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ],
    );
  }
}

class IconBox extends StatelessWidget {
  const IconBox({super.key, required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.lightGreen, borderRadius: BorderRadius.circular(16)),
      child: Icon(icon, color: AppColors.green, size: 30),
    );
  }
}

class PageIntroCard extends StatelessWidget {
  const PageIntroCard({super.key, required this.icon, required this.title, required this.description});

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: cardDecoration(color: AppColors.green),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.16), borderRadius: BorderRadius.circular(16)),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.notoSansKhmer(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(description, style: GoogleFonts.notoSansKhmer(color: Colors.white.withOpacity(0.94), height: 1.55)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ResultCard extends StatelessWidget {
  const ResultCard({super.key, required this.crop, required this.result});

  final String crop;
  final DiseaseResult result;

  @override
  Widget build(BuildContext context) {
    final confidencePercent = (result.confidence * 100).round();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_rounded, color: AppColors.green, size: 30),
              const SizedBox(width: 8),
              Expanded(
                child: Text('លទ្ធផល AI', style: GoogleFonts.moul(fontSize: 19, color: AppColors.darkGreen)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          InfoLine(label: 'ដំណាំ', value: crop),
          InfoLine(label: 'ជំងឺដែលអាចកើតឡើង', value: result.disease),
          InfoLine(label: 'Confidence', value: '$confidencePercent%'),
          InfoLine(label: 'កម្រិតហានិភ័យ', value: result.severity),
          const Divider(height: 26),
          Text('ការណែនាំ', style: GoogleFonts.notoSansKhmer(fontWeight: FontWeight.bold, color: AppColors.darkGreen)),
          const SizedBox(height: 6),
          Text(result.recommendation, style: GoogleFonts.notoSansKhmer(height: 1.6)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFFF8E1), borderRadius: BorderRadius.circular(14)),
            child: Text(
              'ចំណាំ: លទ្ធផលនេះជាការប៉ាន់ស្មានដោយ AI។ សូមពិគ្រោះអ្នកជំនាញមុនប្រើថ្នាំកសិកម្ម។',
              style: GoogleFonts.notoSansKhmer(color: const Color(0xFF795548), height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class ScanHistoryCard extends StatelessWidget {
  const ScanHistoryCard({super.key, required this.record});

  final ScanRecord record;

  @override
  Widget build(BuildContext context) {
    return CompactCard(
      icon: Icons.health_and_safety,
      title: '${record.crop} • ${record.disease}',
      subtitle: 'Confidence ${(record.confidence * 100).round()}% • ${record.severity} • ${formatDate(record.createdAt)}',
    );
  }
}



class SupplyAiPrediction {
  const SupplyAiPrediction({
    required this.cropKh,
    required this.provinceKh,
    required this.harvestMonth,
    required this.harvestYear,
    required this.predictedSupplyKg,
    required this.listedSupplyKg,
    required this.buyerDemandKg,
    required this.dealQuantityKg,
    required this.netBalanceKg,
    required this.averageMarketPrice,
    required this.averageTargetPrice,
    required this.plantingRecords,
    required this.productPosts,
    required this.demandPosts,
    required this.dealRecords,
    required this.statusKh,
    required this.riskLevelKh,
    required this.confidenceScore,
    required this.marketSignalKh,
    required this.recommendationKh,
    required this.actionItemsKh,
    required this.priceStrategyKh,
    required this.dataQualityKh,
  });

  final String cropKh;
  final String provinceKh;
  final int harvestMonth;
  final int harvestYear;
  final double predictedSupplyKg;
  final double listedSupplyKg;
  final double buyerDemandKg;
  final double dealQuantityKg;
  final double netBalanceKg;
  final double averageMarketPrice;
  final double averageTargetPrice;
  final int plantingRecords;
  final int productPosts;
  final int demandPosts;
  final int dealRecords;
  final String statusKh;
  final String riskLevelKh;
  final double confidenceScore;
  final String marketSignalKh;
  final String recommendationKh;
  final List<String> actionItemsKh;
  final String priceStrategyKh;
  final String dataQualityKh;

  factory SupplyAiPrediction.fromJson(Map<String, dynamic> json) {
    double toDouble(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    int toInt(dynamic value) {
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    List<String> toList(dynamic value) {
      if (value is List) {
        return value.map((item) => item.toString().trim()).where((item) => item.isNotEmpty).toList();
      }
      if (value is String && value.trim().isNotEmpty) return [value.trim()];
      return const [];
    }

    return SupplyAiPrediction(
      cropKh: json['crop_kh']?.toString() ?? 'មិនស្គាល់',
      provinceKh: json['province_kh']?.toString() ?? 'មិនស្គាល់',
      harvestMonth: toInt(json['harvest_month']),
      harvestYear: toInt(json['harvest_year']),
      predictedSupplyKg: toDouble(json['predicted_supply_kg']),
      listedSupplyKg: toDouble(json['listed_supply_kg']),
      buyerDemandKg: toDouble(json['buyer_demand_kg']),
      dealQuantityKg: toDouble(json['deal_quantity_kg']),
      netBalanceKg: toDouble(json['net_balance_kg']),
      averageMarketPrice: toDouble(json['average_market_price']),
      averageTargetPrice: toDouble(json['average_target_price']),
      plantingRecords: toInt(json['planting_records']),
      productPosts: toInt(json['product_posts']),
      demandPosts: toInt(json['demand_posts']),
      dealRecords: toInt(json['deal_records']),
      statusKh: json['status_kh']?.toString() ?? 'មិនច្បាស់',
      riskLevelKh: json['risk_level_kh']?.toString() ?? 'មិនច្បាស់',
      confidenceScore: toDouble(json['confidence_score']).clamp(0.0, 1.0).toDouble(),
      marketSignalKh: json['market_signal_kh']?.toString() ?? '',
      recommendationKh: json['recommendation_kh']?.toString() ?? '',
      actionItemsKh: toList(json['action_items_kh']),
      priceStrategyKh: json['price_strategy_kh']?.toString() ?? '',
      dataQualityKh: json['data_quality_kh']?.toString() ?? '',
    );
  }
}

class SupplyPredictorService {
  SupplyPredictorService({http.Client? client}) : _client = client ?? http.Client();

  static final Uri _functionUri = Uri.parse(
    'https://asia-southeast1-kasiai-33c68.cloudfunctions.net/predictSupplyHttp',
  );

  final http.Client _client;

  Future<SupplyAiPrediction> predict({
    required String crop,
    required String province,
    required int harvestYear,
    required int harvestMonth,
    required String userId,
  }) async {
    final response = await _client
        .post(
          _functionUri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'crop': crop,
            'province': province,
            'harvestYear': harvestYear,
            'harvestMonth': harvestMonth,
            'userId': userId,
          }),
        )
        .timeout(const Duration(seconds: 120));

    final decoded = response.body.trim().isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errorBody = decoded is Map ? decoded['error'] : null;
      final message = errorBody is Map
          ? (errorBody['message']?.toString() ?? response.body)
          : response.body;
      throw Exception('AI Supply Cloud error ${response.statusCode}: $message');
    }

    if (decoded is Map<String, dynamic>) {
      return SupplyAiPrediction.fromJson(decoded);
    }
    if (decoded is Map) {
      return SupplyAiPrediction.fromJson(decoded.map((key, value) => MapEntry(key.toString(), value)));
    }
    throw Exception('AI Supply result មិនត្រឹមត្រូវ');
  }
}

class AiSupplyPredictionCard extends StatelessWidget {
  const AiSupplyPredictionCard({super.key, required this.prediction});

  final SupplyAiPrediction prediction;

  @override
  Widget build(BuildContext context) {
    final confidence = (prediction.confidenceScore * 100).round();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightGreen,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.green.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const IconBox(icon: Icons.auto_awesome_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AI Supply Intelligence', style: GoogleFonts.notoSansKhmer(fontWeight: FontWeight.bold, color: AppColors.darkGreen, fontSize: 17)),
                    Text('${prediction.cropKh} • ${prediction.provinceKh} • ខែ ${prediction.harvestMonth}/${prediction.harvestYear}', style: GoogleFonts.notoSansKhmer(color: AppColors.muted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          InfoLine(label: 'ស្ថានភាព', value: prediction.statusKh),
          InfoLine(label: 'Risk', value: prediction.riskLevelKh),
          InfoLine(label: 'Confidence', value: '$confidence%'),
          InfoLine(label: 'Supply', value: '${prediction.predictedSupplyKg.toStringAsFixed(0)} kg'),
          InfoLine(label: 'Buyer demand', value: '${prediction.buyerDemandKg.toStringAsFixed(0)} kg'),
          InfoLine(label: 'Net balance', value: '${prediction.netBalanceKg.toStringAsFixed(0)} kg'),
          if (prediction.averageMarketPrice > 0) InfoLine(label: 'Avg market price', value: '\$${prediction.averageMarketPrice.toStringAsFixed(2)}/kg'),
          const Divider(height: 22),
          Text('Market Signal', style: GoogleFonts.notoSansKhmer(fontWeight: FontWeight.bold, color: AppColors.darkGreen)),
          Text(prediction.marketSignalKh, style: GoogleFonts.notoSansKhmer(height: 1.5)),
          const SizedBox(height: 8),
          Text('Recommendation', style: GoogleFonts.notoSansKhmer(fontWeight: FontWeight.bold, color: AppColors.darkGreen)),
          Text(prediction.recommendationKh, style: GoogleFonts.notoSansKhmer(height: 1.5)),
          if (prediction.priceStrategyKh.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Price Strategy', style: GoogleFonts.notoSansKhmer(fontWeight: FontWeight.bold, color: AppColors.darkGreen)),
            Text(prediction.priceStrategyKh, style: GoogleFonts.notoSansKhmer(height: 1.5)),
          ],
          if (prediction.actionItemsKh.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Action Plan', style: GoogleFonts.notoSansKhmer(fontWeight: FontWeight.bold, color: AppColors.darkGreen)),
            ...prediction.actionItemsKh.map((item) => Text('• $item', style: GoogleFonts.notoSansKhmer(height: 1.5))),
          ],
          const SizedBox(height: 8),
          Text('Data: ${prediction.plantingRecords} planting • ${prediction.productPosts} products • ${prediction.demandPosts} demands • ${prediction.dealRecords} deals', style: GoogleFonts.notoSansKhmer(color: AppColors.muted, fontSize: 12)),
          if (prediction.dataQualityKh.isNotEmpty)
            Text(prediction.dataQualityKh, style: GoogleFonts.notoSansKhmer(color: AppColors.muted, fontSize: 12, height: 1.5)),
        ],
      ),
    );
  }
}

class CloudErrorCard extends StatelessWidget {
  const CloudErrorCard({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFCDD2)),
      ),
      child: Text(message, style: GoogleFonts.notoSansKhmer(color: const Color(0xFFC62828), height: 1.5)),
    );
  }
}

class ForecastCard extends StatelessWidget {
  const ForecastCard({super.key, required this.summary});

  final ForecastSummary summary;

  @override
  Widget build(BuildContext context) {
    final isHigh = summary.expectedKg >= 5000 || summary.recordCount >= 3;
    final isMedium = summary.expectedKg >= 1000 && !isHigh;
    final status = isHigh ? 'ផ្គត់ផ្គង់ខ្ពស់' : (isMedium ? 'ផ្គត់ផ្គង់មធ្យម' : 'ផ្គត់ផ្គង់ទាប');
    final message = isHigh
        ? 'អាចមានការផ្គត់ផ្គង់លើសនៅខែនេះ។ គួររកអ្នកទិញមុន ឬភ្ជាប់ទៅ Marketplace។'
        : isMedium
            ? 'ការផ្គត់ផ្គង់ស្ថិតក្នុងកម្រិតមធ្យម។ បន្តតាមដានតម្រូវការទីផ្សារ។'
            : 'ទិន្នផលរំពឹងទុកនៅតិច។ អាចមានឱកាសលក់តម្លៃល្អ ប្រសិនបើតម្រូវការខ្ពស់។';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBox(icon: isHigh ? Icons.warning_amber_rounded : Icons.trending_up),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${summary.crop} • ${summary.province}',
                  style: GoogleFonts.notoSansKhmer(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.darkGreen),
                ),
                Text(
                  'ខែ ${summary.harvestMonth}/${summary.harvestYear} • ${summary.recordCount} កំណត់ត្រា',
                  style: GoogleFonts.notoSansKhmer(color: AppColors.muted),
                ),
                Text(
                  'រំពឹងទិន្នផលសរុប: ${summary.expectedKg.toStringAsFixed(0)} kg',
                  style: GoogleFonts.notoSansKhmer(color: AppColors.muted),
                ),
                const SizedBox(height: 4),
                Text(status, style: GoogleFonts.notoSansKhmer(fontWeight: FontWeight.bold, color: AppColors.green)),
                const SizedBox(height: 4),
                Text(message, style: GoogleFonts.notoSansKhmer(height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PlantingRecordCard extends StatelessWidget {
  const PlantingRecordCard({super.key, required this.record});

  final PlantingRecord record;

  @override
  Widget build(BuildContext context) {
    return CompactCard(
      icon: Icons.grass,
      title: '${record.crop} • ${record.province}',
      subtitle: '${record.area} ha • ${record.expectedKg.toStringAsFixed(0)} kg • ប្រមូលផល ${formatDate(record.harvestDate)}',
    );
  }
}


class ProductPhotoPreview extends StatelessWidget {
  const ProductPhotoPreview({super.key, required this.photoBase64, this.height = 130});

  final String photoBase64;
  final double height;

  @override
  Widget build(BuildContext context) {
    final imageProvider = imageProviderFromBase64OrUrl(photoBase64, '');
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.lightGreen,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        image: imageProvider == null
            ? null
            : DecorationImage(image: imageProvider, fit: BoxFit.cover),
      ),
      child: imageProvider == null
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.add_photo_alternate_rounded, color: AppColors.green, size: 38),
                const SizedBox(height: 6),
                Text('បន្ថែមរូបផលិតផល', style: GoogleFonts.notoSansKhmer(color: AppColors.green)),
              ],
            )
          : null,
    );
  }
}



class PagedList<T> extends StatefulWidget {
  const PagedList({super.key, required this.items, required this.itemBuilder, this.pageSize = 10});

  final List<T> items;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final int pageSize;

  @override
  State<PagedList<T>> createState() => _PagedListState<T>();
}

class _PagedListState<T> extends State<PagedList<T>> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final totalPages = (widget.items.length / widget.pageSize).ceil().clamp(1, 9999).toInt();
    if (_page >= totalPages) _page = totalPages - 1;
    final start = _page * widget.pageSize;
    final end = (start + widget.pageSize).clamp(0, widget.items.length).toInt();
    final pageItems = widget.items.sublist(start, end);

    return Column(
      children: [
        ...pageItems.map((item) => widget.itemBuilder(context, item)),
        if (widget.items.length > widget.pageSize) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: cardDecoration(),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _page == 0 ? null : () => setState(() => _page -= 1),
                    icon: const Icon(Icons.chevron_left),
                    label: const Text('Previous'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text('${_page + 1}/$totalPages', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: AppColors.darkGreen)),
                ),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _page >= totalPages - 1 ? null : () => setState(() => _page += 1),
                    icon: const Icon(Icons.chevron_right),
                    label: const Text('Next'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

Future<ProductListing?> showProductListingEditorDialog(BuildContext context, {ProductListing? existing}) async {
  String crop = existing?.crop ?? kCambodianCrops[1];
  String province = existing?.province ?? kCambodianProvinces[2];
  String grade = existing?.grade ?? 'Grade A';
  String productPhotoBase64 = existing?.photoBase64 ?? '';
  DateTime harvestDate = existing?.harvestDate ?? DateTime.now().add(const Duration(days: 20));
  final qtyController = TextEditingController(text: existing?.quantity.toStringAsFixed(0) ?? '500');
  final priceController = TextEditingController(text: existing?.price.toStringAsFixed(2) ?? '0.85');
  final descriptionController = TextEditingController(text: existing?.description ?? '');

  final result = await showDialog<ProductListing>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> pickProductPhoto(ImageSource source) async {
            final picked = await ImagePicker().pickImage(
              source: source,
              imageQuality: 65,
              maxWidth: 900,
              maxHeight: 900,
            );
            if (picked == null) return;
            final bytes = await File(picked.path).readAsBytes();
            setDialogState(() => productPhotoBase64 = base64Encode(bytes));
          }

          return AlertDialog(
            title: Text(existing == null ? 'បង្ហោះផលិតផល' : 'កែប្រែផលិតផល'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: productPhotoBase64.isEmpty ? null : () => showFullImage(context, productPhotoBase64, ''),
                    child: ProductPhotoPreview(photoBase64: productPhotoBase64),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => pickProductPhoto(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('Camera'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => pickProductPhoto(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library),
                          label: const Text('Gallery'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: crop,
                    decoration: const InputDecoration(labelText: 'ឈ្មោះដំណាំ'),
                    items: kCambodianCrops.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
                    onChanged: (value) => setDialogState(() => crop = value ?? crop),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: province,
                    decoration: const InputDecoration(labelText: 'ខេត្ត / រាជធានី'),
                    items: kCambodianProvinces.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
                    onChanged: (value) => setDialogState(() => province = value ?? province),
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: qtyController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'ចំនួន kg')),
                  const SizedBox(height: 10),
                  TextField(controller: priceController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'តម្លៃ \$/kg')),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: grade,
                    decoration: const InputDecoration(labelText: 'គុណភាព'),
                    items: ['Grade A', 'Grade B', 'Grade C'].map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
                    onChanged: (value) => setDialogState(() => grade = value ?? grade),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descriptionController,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'ពិពណ៌នាផលិតផល / លក្ខខណ្ឌ'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: dialogContext,
                        initialDate: harvestDate,
                        firstDate: DateTime.now().subtract(const Duration(days: 1)),
                        lastDate: DateTime(2028, 12, 31),
                      );
                      if (picked != null) setDialogState(() => harvestDate = picked);
                    },
                    icon: const Icon(Icons.calendar_month),
                    label: Text('ថ្ងៃប្រមូលផល: ${formatDate(harvestDate)}'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('បោះបង់')),
              FilledButton(
                onPressed: () {
                  final qty = double.tryParse(qtyController.text.trim()) ?? 0;
                  final price = double.tryParse(priceController.text.trim()) ?? 0;
                  if (qty <= 0 || price <= 0) return;
                  final user = FirebaseAuth.instance.currentUser;
                  Navigator.pop(
                    dialogContext,
                    ProductListing(
                      id: existing?.id ?? DateTime.now().millisecondsSinceEpoch,
                      documentId: existing?.documentId,
                      crop: crop,
                      province: province,
                      quantity: qty,
                      unit: existing?.unit ?? 'kg',
                      price: price,
                      grade: grade,
                      harvestDate: harvestDate,
                      farmerName: existing?.farmerName ?? (user?.displayName?.trim().isNotEmpty == true ? user!.displayName! : (user?.email ?? 'កសិករ')),
                      userId: existing?.userId ?? user?.uid ?? '',
                      userEmail: existing?.userEmail ?? user?.email ?? '',
                      photoBase64: productPhotoBase64,
                      description: descriptionController.text.trim(),
                      farmerPhone: existing?.farmerPhone ?? '',
                      farmerProvince: existing?.farmerProvince ?? '',
                      farmerRole: existing?.farmerRole ?? '',
                      farmerPhotoBase64: existing?.farmerPhotoBase64 ?? '',
                      farmerPhotoUrl: existing?.farmerPhotoUrl ?? '',
                      status: existing?.status ?? 'Active',
                      active: existing?.active ?? true,
                    ),
                  );
                },
                child: Text(existing == null ? 'រក្សាទុក' : 'កែប្រែ'),
              ),
            ],
          );
        },
      );
    },
  );

  qtyController.dispose();
  priceController.dispose();
  descriptionController.dispose();
  return result;
}

Future<BuyingDemand?> showBuyingDemandEditorDialog(BuildContext context, {BuyingDemand? existing}) async {
  String crop = existing?.crop ?? kCambodianCrops[1];
  String province = existing?.province ?? kCambodianProvinces.first;
  DateTime deliveryDate = existing?.deliveryDate ?? DateTime.now().add(const Duration(days: 15));
  final qtyController = TextEditingController(text: existing?.quantity.toStringAsFixed(0) ?? '500');
  final priceController = TextEditingController(text: existing?.targetPrice.toStringAsFixed(2) ?? '1.10');
  final descriptionController = TextEditingController(text: existing?.description ?? '');

  final result = await showDialog<BuyingDemand>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: Text(existing == null ? 'បង្ហោះតម្រូវការទិញ' : 'កែប្រែតម្រូវការ'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: crop,
                    decoration: const InputDecoration(labelText: 'ត្រូវការដំណាំ'),
                    items: kCambodianCrops.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
                    onChanged: (value) => setDialogState(() => crop = value ?? crop),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: province,
                    decoration: const InputDecoration(labelText: 'ខេត្ត / រាជធានី'),
                    items: kCambodianProvinces.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
                    onChanged: (value) => setDialogState(() => province = value ?? province),
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: qtyController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'ចំនួន kg')),
                  const SizedBox(height: 10),
                  TextField(controller: priceController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'តម្លៃគោលដៅ \$/kg')),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descriptionController,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'ពិពណ៌នាតម្រូវការ / លក្ខខណ្ឌ'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: dialogContext,
                        initialDate: deliveryDate,
                        firstDate: DateTime.now().subtract(const Duration(days: 1)),
                        lastDate: DateTime(2028, 12, 31),
                      );
                      if (picked != null) setDialogState(() => deliveryDate = picked);
                    },
                    icon: const Icon(Icons.calendar_month),
                    label: Text('ថ្ងៃត្រូវការ: ${formatDate(deliveryDate)}'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('បោះបង់')),
              FilledButton(
                onPressed: () {
                  final qty = double.tryParse(qtyController.text.trim()) ?? 0;
                  final price = double.tryParse(priceController.text.trim()) ?? 0;
                  if (qty <= 0 || price <= 0) return;
                  final user = FirebaseAuth.instance.currentUser;
                  Navigator.pop(
                    dialogContext,
                    BuyingDemand(
                      id: existing?.id ?? DateTime.now().millisecondsSinceEpoch,
                      documentId: existing?.documentId,
                      crop: crop,
                      province: province,
                      quantity: qty,
                      unit: existing?.unit ?? 'kg',
                      targetPrice: price,
                      buyerName: existing?.buyerName ?? (user?.displayName?.trim().isNotEmpty == true ? user!.displayName! : (user?.email ?? 'អ្នកទិញ')),
                      deliveryDate: deliveryDate,
                      userId: existing?.userId ?? user?.uid ?? '',
                      userEmail: existing?.userEmail ?? user?.email ?? '',
                      description: descriptionController.text.trim(),
                      buyerPhone: existing?.buyerPhone ?? '',
                      buyerProvince: existing?.buyerProvince ?? '',
                      buyerRole: existing?.buyerRole ?? '',
                      buyerPhotoBase64: existing?.buyerPhotoBase64 ?? '',
                      buyerPhotoUrl: existing?.buyerPhotoUrl ?? '',
                      status: existing?.status ?? 'Active',
                      active: existing?.active ?? true,
                    ),
                  );
                },
                child: Text(existing == null ? 'រក្សាទុក' : 'កែប្រែ'),
              ),
            ],
          );
        },
      );
    },
  );

  qtyController.dispose();
  priceController.dispose();
  descriptionController.dispose();
  return result;
}

class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    required this.onDeal,
    required this.onEdit,
    required this.onDelete,
  });

  final ProductListing product;
  final VoidCallback onDeal;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final isOwner = currentUser != null && currentUser.uid == product.userId;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: product.photoBase64.isEmpty ? null : () => showFullImage(context, product.photoBase64, ''),
            child: ProductPhotoPreview(photoBase64: product.photoBase64, height: 160),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(product.crop, style: GoogleFonts.notoSansKhmer(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.darkGreen)),
              ),
              if (isOwner)
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') onEdit();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit Post')),
                    PopupMenuItem(value: 'delete', child: Text('Delete Post')),
                  ],
                ),
            ],
          ),
          if (product.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(product.description, style: GoogleFonts.notoSansKhmer(color: AppColors.muted, fontSize: 13, height: 1.4)),
          ],
          const SizedBox(height: 10),
          MarketplaceProfileLine(
            title: product.farmerName,
            subtitle: [product.farmerRole, product.farmerProvince, product.farmerPhone].where((item) => item.trim().isNotEmpty).join(' • '),
            photoBase64: product.farmerPhotoBase64,
            photoUrl: product.farmerPhotoUrl,
            onTap: () => showUserProfileSheet(
              context,
              userId: product.userId,
              fallbackName: product.farmerName,
              fallbackEmail: product.userEmail,
              fallbackPhone: product.farmerPhone,
              fallbackProvince: product.farmerProvince,
              fallbackRole: product.farmerRole,
              fallbackPhotoBase64: product.farmerPhotoBase64,
              fallbackPhotoUrl: product.farmerPhotoUrl,
            ),
          ),
          const SizedBox(height: 10),
          InfoLine(label: 'ទីតាំង', value: product.province),
          InfoLine(label: 'ចំនួន', value: '${product.quantity.toStringAsFixed(0)} ${product.unit}'),
          InfoLine(label: 'តម្លៃ', value: '${money(product.price)}/${product.unit}'),
          InfoLine(label: 'Grade', value: product.grade),
          InfoLine(label: 'ថ្ងៃប្រមូលផល', value: formatDate(product.harvestDate)),
          const SizedBox(height: 10),
          PostInteractionBar(
            collectionName: 'product_listings',
            documentId: product.documentId,
            ownerId: product.userId,
            postTitle: product.crop,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => showUserProfileSheet(
                    context,
                    userId: product.userId,
                    fallbackName: product.farmerName,
                    fallbackEmail: product.userEmail,
                    fallbackPhone: product.farmerPhone,
                    fallbackProvince: product.farmerProvince,
                    fallbackRole: product.farmerRole,
                    fallbackPhotoBase64: product.farmerPhotoBase64,
                    fallbackPhotoUrl: product.farmerPhotoUrl,
                  ),
                  icon: const Icon(Icons.person),
                  label: const Text('Profile'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: isOwner
                    ? OutlinedButton.icon(onPressed: onEdit, icon: const Icon(Icons.edit), label: const Text('Edit'))
                    : FilledButton.icon(onPressed: onDeal, icon: const Icon(Icons.handshake), label: const Text('Request Deal')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class DemandCard extends StatelessWidget {
  const DemandCard({
    super.key,
    required this.demand,
    required this.matchCount,
    required this.onDeal,
    required this.onEdit,
    required this.onDelete,
  });

  final BuyingDemand demand;
  final int matchCount;
  final VoidCallback onDeal;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final isOwner = currentUser != null && currentUser.uid == demand.userId;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text('ត្រូវការ ${demand.crop}', style: GoogleFonts.notoSansKhmer(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.darkGreen)),
              ),
              if (isOwner)
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') onEdit();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit Post')),
                    PopupMenuItem(value: 'delete', child: Text('Delete Post')),
                  ],
                ),
            ],
          ),
          if (demand.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(demand.description, style: GoogleFonts.notoSansKhmer(color: AppColors.muted, fontSize: 13, height: 1.4)),
          ],
          const SizedBox(height: 10),
          MarketplaceProfileLine(
            title: demand.buyerName,
            subtitle: [demand.buyerRole, demand.buyerProvince, demand.buyerPhone].where((item) => item.trim().isNotEmpty).join(' • '),
            photoBase64: demand.buyerPhotoBase64,
            photoUrl: demand.buyerPhotoUrl,
            onTap: () => showUserProfileSheet(
              context,
              userId: demand.userId,
              fallbackName: demand.buyerName,
              fallbackEmail: demand.userEmail,
              fallbackPhone: demand.buyerPhone,
              fallbackProvince: demand.buyerProvince,
              fallbackRole: demand.buyerRole,
              fallbackPhotoBase64: demand.buyerPhotoBase64,
              fallbackPhotoUrl: demand.buyerPhotoUrl,
            ),
          ),
          const SizedBox(height: 10),
          InfoLine(label: 'ទីតាំង', value: demand.province),
          InfoLine(label: 'ចំនួន', value: '${demand.quantity.toStringAsFixed(0)} ${demand.unit}'),
          InfoLine(label: 'Target price', value: '${money(demand.targetPrice)}/kg'),
          InfoLine(label: 'Matching product', value: '$matchCount'),
          InfoLine(label: 'ថ្ងៃត្រូវការ', value: formatDate(demand.deliveryDate)),
          const SizedBox(height: 10),
          PostInteractionBar(
            collectionName: 'buying_demands',
            documentId: demand.documentId,
            ownerId: demand.userId,
            postTitle: demand.crop,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => showUserProfileSheet(
                    context,
                    userId: demand.userId,
                    fallbackName: demand.buyerName,
                    fallbackEmail: demand.userEmail,
                    fallbackPhone: demand.buyerPhone,
                    fallbackProvince: demand.buyerProvince,
                    fallbackRole: demand.buyerRole,
                    fallbackPhotoBase64: demand.buyerPhotoBase64,
                    fallbackPhotoUrl: demand.buyerPhotoUrl,
                  ),
                  icon: const Icon(Icons.person),
                  label: const Text('Profile'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: isOwner
                    ? OutlinedButton.icon(onPressed: onEdit, icon: const Icon(Icons.edit), label: const Text('Edit'))
                    : FilledButton.icon(onPressed: onDeal, icon: const Icon(Icons.connect_without_contact), label: const Text('Match Deal')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


class DealCard extends StatelessWidget {
  const DealCard({super.key, required this.deal});

  final DealRecord deal;

  Future<void> _updateStatus(BuildContext context, String status) async {
    if (deal.documentId == null) return;
    final user = FirebaseAuth.instance.currentUser;
    final isParticipant = user != null && (deal.buyerId == user.uid || deal.farmerId == user.uid);
    if (!isParticipant) {
      showMessage(context, 'អ្នកអាចកែ Deal ដែលពាក់ព័ន្ធនឹងគណនីអ្នកប៉ុណ្ណោះ');
      return;
    }

    await FirebaseFirestore.instance.collection('deals').doc(deal.documentId).set({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (status == 'Completed') {
      if (deal.productId.isNotEmpty) {
        await FirebaseFirestore.instance.collection('product_listings').doc(deal.productId).set({
          'active': false,
          'status': 'Completed',
          'closedByDealId': deal.documentId,
          'closedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      if (deal.demandId.isNotEmpty) {
        await FirebaseFirestore.instance.collection('buying_demands').doc(deal.demandId).set({
          'active': false,
          'status': 'Completed',
          'closedByDealId': deal.documentId,
          'closedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }

    final targetUserId = user?.uid == deal.buyerId ? deal.farmerId : deal.buyerId;
    await createMarketplaceNotification(
      toUserId: targetUserId,
      title: 'Deal បានប្ដូរស្ថានភាព',
      message: '${deal.crop} Deal បានប្ដូរទៅ $status',
      type: 'deal_status',
      referenceCollection: 'deals',
      referenceId: deal.documentId ?? '',
    );

    if (context.mounted) showMessage(context, 'បានប្ដូរស្ថានភាព Deal ទៅ $status');
  }

  @override
  Widget build(BuildContext context) {
    final productImage = imageProviderFromBase64OrUrl(deal.productPhotoBase64, '');
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (productImage != null) ...[
            GestureDetector(
              onTap: () => showFullImage(context, deal.productPhotoBase64, ''),
              child: Container(
                height: 140,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  image: DecorationImage(image: productImage, fit: BoxFit.cover),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Text('${deal.crop} Deal', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.darkGreen)),
          const SizedBox(height: 8),
          MarketplaceProfileLine(
            title: deal.farmerName,
            subtitle: 'Farmer • ${deal.farmerPhone}',
            photoBase64: deal.farmerPhotoBase64,
            photoUrl: deal.farmerPhotoUrl,
            onTap: () => showUserProfileSheet(
              context,
              userId: deal.farmerId,
              fallbackName: deal.farmerName,
              fallbackEmail: deal.farmerEmail,
              fallbackPhone: deal.farmerPhone,
              fallbackProvince: deal.farmerProvince,
              fallbackRole: deal.farmerRole,
              fallbackPhotoBase64: deal.farmerPhotoBase64,
              fallbackPhotoUrl: deal.farmerPhotoUrl,
            ),
          ),
          const SizedBox(height: 8),
          MarketplaceProfileLine(
            title: deal.buyerName,
            subtitle: 'Buyer • ${deal.buyerPhone}',
            photoBase64: deal.buyerPhotoBase64,
            photoUrl: deal.buyerPhotoUrl,
            onTap: () => showUserProfileSheet(
              context,
              userId: deal.buyerId,
              fallbackName: deal.buyerName,
              fallbackEmail: deal.buyerEmail,
              fallbackPhone: deal.buyerPhone,
              fallbackProvince: deal.buyerProvince,
              fallbackRole: deal.buyerRole,
              fallbackPhotoBase64: deal.buyerPhotoBase64,
              fallbackPhotoUrl: deal.buyerPhotoUrl,
            ),
          ),
          const Divider(height: 22),
          InfoLine(label: 'Quantity', value: '${deal.quantity.toStringAsFixed(0)} kg'),
          InfoLine(label: 'Deal value', value: money(deal.value)),
          InfoLine(label: 'Commission 2%', value: money(deal.commission)),
          InfoLine(label: 'Status', value: deal.status),
          if (deal.note.isNotEmpty) InfoLine(label: 'Note', value: deal.note),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 520;
              final halfWidth = (constraints.maxWidth - 10) / 2;

              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: isWide ? 140 : halfWidth,
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: () => showDealChatSheet(context, deal),
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Chat'),
                    ),
                  ),
                  SizedBox(
                    width: isWide ? 165 : halfWidth,
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: deal.status == 'Completed' ? null : () => _updateStatus(context, 'Confirmed'),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Confirm'),
                    ),
                  ),
                  SizedBox(
                    width: isWide ? constraints.maxWidth - 325 : constraints.maxWidth,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: deal.status == 'Completed' ? null : () => _updateStatus(context, 'Completed'),
                      icon: const Icon(Icons.done_all),
                      label: const Text('Complete'),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class MarketplaceProfileLine extends StatelessWidget {
  const MarketplaceProfileLine({
    super.key,
    required this.title,
    required this.subtitle,
    required this.photoBase64,
    required this.photoUrl,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String photoBase64;
  final String photoUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final imageProvider = imageProviderFromBase64OrUrl(photoBase64, photoUrl);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: AppColors.lightGreen, borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: Colors.white,
              backgroundImage: imageProvider,
              child: imageProvider == null ? const Icon(Icons.person, color: AppColors.green) : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title.isEmpty ? 'KasiAI User' : title, style: GoogleFonts.notoSansKhmer(fontWeight: FontWeight.bold, color: AppColors.darkGreen), overflow: TextOverflow.ellipsis),
                  if (subtitle.trim().isNotEmpty)
                    Text(subtitle, style: GoogleFonts.notoSansKhmer(color: AppColors.muted, fontSize: 12), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.green),
          ],
        ),
      ),
    );
  }
}

class PriceCard extends StatelessWidget {
  const PriceCard({super.key, required this.price});

  final MarketPrice price;

  @override
  Widget build(BuildContext context) {
    return CompactCard(
      icon: Icons.price_change,
      title: price.crop,
      subtitle: '${money(price.price)}/kg • Trend ${price.trend}',
    );
  }
}

class ProfitRecordCard extends StatelessWidget {
  const ProfitRecordCard({super.key, required this.record});

  final ProfitRecord record;

  @override
  Widget build(BuildContext context) {
    final isIncome = record.type == ProfitType.income;
    return CompactCard(
      icon: isIncome ? Icons.arrow_downward : Icons.arrow_upward,
      title: record.title,
      subtitle: '${isIncome ? 'ចំណូល' : 'ចំណាយ'} • ${money(record.amount)}',
      iconColor: isIncome ? AppColors.green : AppColors.danger,
    );
  }
}

class CompactCard extends StatelessWidget {
  const CompactCard({super.key, required this.icon, required this.title, required this.subtitle, this.iconColor});

  final IconData icon;
  final String title;
  final String subtitle;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: cardDecoration(),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.lightGreen, borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: iconColor ?? AppColors.green),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.notoSansKhmer(fontWeight: FontWeight.bold, color: AppColors.text)),
                const SizedBox(height: 2),
                Text(subtitle, style: GoogleFonts.notoSansKhmer(color: AppColors.muted, fontSize: 12, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SummaryBox extends StatelessWidget {
  const SummaryBox({super.key, required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.notoSansKhmer(color: AppColors.muted, fontSize: 12)),
          Text(value, style: GoogleFonts.poppins(color: color, fontWeight: FontWeight.bold, fontSize: 18)),
        ],
      ),
    );
  }
}

class InfoLine extends StatelessWidget {
  const InfoLine({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: GoogleFonts.notoSansKhmer(color: AppColors.muted, fontSize: 13)),
          ),
          Expanded(
            child: Text(value, style: GoogleFonts.notoSansKhmer(fontWeight: FontWeight.w600, color: AppColors.text, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class ListWithAction extends StatelessWidget {
  const ListWithAction({super.key, required this.buttonLabel, required this.onPressed, required this.child});

  final String buttonLabel;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(onPressed: onPressed, icon: const Icon(Icons.add), label: Text(buttonLabel)),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: cardDecoration(),
      child: Column(
        children: [
          const Icon(Icons.inbox_rounded, color: AppColors.muted, size: 42),
          const SizedBox(height: 10),
          Text(text, textAlign: TextAlign.center, style: GoogleFonts.notoSansKhmer(color: AppColors.muted)),
        ],
      ),
    );
  }
}

BoxDecoration cardDecoration({Color color = Colors.white}) {
  return BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(22),
    border: color == Colors.white ? Border.all(color: AppColors.border) : null,
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.04),
        blurRadius: 12,
        offset: const Offset(0, 6),
      ),
    ],
  );
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}




Future<bool> showConfirmDialog(BuildContext context, String title, String message) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('OK')),
      ],
    ),
  );
  return result ?? false;
}

void showFullImage(BuildContext context, String base64Value, String url) {
  final imageProvider = imageProviderFromBase64OrUrl(base64Value, url);
  if (imageProvider == null) return;
  showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.all(12),
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          InteractiveViewer(
            child: Center(
              child: Image(image: imageProvider, fit: BoxFit.contain),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton.filled(
              onPressed: () => Navigator.pop(dialogContext),
              icon: const Icon(Icons.close),
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> createMarketplaceNotification({
  required String toUserId,
  required String title,
  required String message,
  required String type,
  String referenceCollection = '',
  String referenceId = '',
}) async {
  final currentUser = FirebaseAuth.instance.currentUser;
  if (toUserId.trim().isEmpty || currentUser == null || toUserId == currentUser.uid) return;
  final profile = await currentUserMarketplaceProfile(currentUser);
  await FirebaseFirestore.instance.collection('notifications').add({
    'userId': toUserId,
    'fromUserId': currentUser.uid,
    'fromName': profile['name'],
    'title': title,
    'message': message,
    'type': type,
    'referenceCollection': referenceCollection,
    'referenceId': referenceId,
    'isRead': false,
    'createdAt': FieldValue.serverTimestamp(),
  });
}

class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        final count = (snapshot.data?.docs ?? []).where((doc) => doc.data()['isRead'] != true).length;
        return Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              tooltip: 'Notifications',
              onPressed: () => showNotificationsSheet(context),
              icon: const Icon(Icons.notifications_rounded),
            ),
            if (count > 0)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: AppColors.amber, borderRadius: BorderRadius.circular(999)),
                  child: Text('$count', style: GoogleFonts.poppins(fontSize: 10, color: AppColors.darkGreen, fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        );
      },
    );
  }
}

Future<void> showNotificationsSheet(BuildContext context) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Notifications', style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.darkGreen))),
                  TextButton(
                    onPressed: () async {
                      final docs = await FirebaseFirestore.instance
                          .collection('notifications')
                          .where('userId', isEqualTo: user.uid)
                          .get();
                      for (final doc in docs.docs.where((doc) => doc.data()['isRead'] != true)) {
                        await doc.reference.set({'isRead': true, 'readAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
                      }
                    },
                    child: const Text('Mark read'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: MediaQuery.of(sheetContext).size.height * 0.65,
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('notifications')
                      .where('userId', isEqualTo: user.uid)
                      .limit(50)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: AppColors.green));
                    }
                    final docs = snapshot.data?.docs ?? [];
                    if (docs.isEmpty) return const EmptyState(text: 'មិនទាន់មាន notification ទេ');
                    return ListView.builder(
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final doc = docs[index];
                        final data = doc.data();
                        final isRead = data['isRead'] == true;
                        return Card(
                          child: ListTile(
                            leading: Icon(isRead ? Icons.notifications_none : Icons.notifications_active, color: AppColors.green),
                            title: Text(data['title']?.toString() ?? 'Notification', style: GoogleFonts.notoSansKhmer(fontWeight: FontWeight.bold)),
                            subtitle: Text(data['message']?.toString() ?? '', style: GoogleFonts.notoSansKhmer()),
                            onTap: () => doc.reference.set({'isRead': true, 'readAt': FieldValue.serverTimestamp()}, SetOptions(merge: true)),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class PostInteractionBar extends StatelessWidget {
  const PostInteractionBar({
    super.key,
    required this.collectionName,
    required this.documentId,
    required this.ownerId,
    required this.postTitle,
  });

  final String collectionName;
  final String? documentId;
  final String ownerId;
  final String postTitle;

  Future<void> _toggleLike(BuildContext context, bool isLiked) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      showMessage(context, 'សូមចូលគណនីជាមុនសិន');
      return;
    }
    if (documentId == null) return;
    final likeRef = FirebaseFirestore.instance.collection(collectionName).doc(documentId).collection('likes').doc(user.uid);
    if (isLiked) {
      await likeRef.delete();
    } else {
      final profile = await currentUserMarketplaceProfile(user);
      await likeRef.set({
        'userId': user.uid,
        'name': profile['name'],
        'createdAt': FieldValue.serverTimestamp(),
      });
      await createMarketplaceNotification(
        toUserId: ownerId,
        title: 'មានអ្នកចូលចិត្ត Post របស់អ្នក',
        message: '${profile['name']} បានចុចចិត្តលើ $postTitle',
        type: 'like',
        referenceCollection: collectionName,
        referenceId: documentId ?? '',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (documentId == null || documentId!.isEmpty) return const SizedBox.shrink();
    final postRef = FirebaseFirestore.instance.collection(collectionName).doc(documentId);
    return Row(
      children: [
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: user == null ? null : postRef.collection('likes').doc(user.uid).snapshots(),
          builder: (context, likeSnapshot) {
            final isLiked = likeSnapshot.data?.exists == true;
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: postRef.collection('likes').snapshots(),
              builder: (context, countSnapshot) {
                final likeCount = countSnapshot.data?.docs.length ?? 0;
                return TextButton.icon(
                  onPressed: () => _toggleLike(context, isLiked),
                  icon: Icon(isLiked ? Icons.favorite : Icons.favorite_border, color: isLiked ? AppColors.danger : AppColors.green),
                  label: Text('$likeCount'),
                );
              },
            );
          },
        ),
        const SizedBox(width: 4),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: postRef.collection('comments').snapshots(),
          builder: (context, snapshot) {
            final commentCount = snapshot.data?.docs.length ?? 0;
            return TextButton.icon(
              onPressed: () => showCommentsSheet(
                context,
                collectionName: collectionName,
                documentId: documentId!,
                ownerId: ownerId,
                postTitle: postTitle,
              ),
              icon: const Icon(Icons.chat_bubble_outline, color: AppColors.green),
              label: Text('$commentCount Comment'),
            );
          },
        ),
      ],
    );
  }
}

Future<void> showCommentsSheet(
  BuildContext context, {
  required String collectionName,
  required String documentId,
  required String ownerId,
  required String postTitle,
}) async {
  final commentController = TextEditingController();
  final postRef = FirebaseFirestore.instance.collection(collectionName).doc(documentId);
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.only(left: 16, right: 16, bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16, top: 8),
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.72,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Comments', style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.darkGreen)),
                const SizedBox(height: 8),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: postRef.collection('comments').orderBy('createdAt', descending: true).snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: AppColors.green));
                      final comments = snapshot.data?.docs ?? [];
                      if (comments.isEmpty) return const Center(child: Text('No comments yet'));
                      return ListView.builder(
                        reverse: true,
                        itemCount: comments.length,
                        itemBuilder: (context, index) {
                          final data = comments[index].data();
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppColors.lightGreen,
                              backgroundImage: imageProviderFromBase64OrUrl(data['photoBase64']?.toString() ?? '', data['photoUrl']?.toString() ?? ''),
                              child: imageProviderFromBase64OrUrl(data['photoBase64']?.toString() ?? '', data['photoUrl']?.toString() ?? '') == null
                                  ? const Icon(Icons.person, color: AppColors.green)
                                  : null,
                            ),
                            title: Text(data['name']?.toString() ?? 'KasiAI User', style: GoogleFonts.notoSansKhmer(fontWeight: FontWeight.bold)),
                            subtitle: Text(data['text']?.toString() ?? '', style: GoogleFonts.notoSansKhmer()),
                          );
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: commentController,
                        decoration: const InputDecoration(labelText: 'Write comment'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () async {
                        final user = FirebaseAuth.instance.currentUser;
                        final text = commentController.text.trim();
                        if (user == null || text.isEmpty) return;
                        final profile = await currentUserMarketplaceProfile(user);
                        await postRef.collection('comments').add({
                          'userId': user.uid,
                          'name': profile['name'],
                          'photoBase64': profile['photoBase64'],
                          'photoUrl': profile['photoUrl'],
                          'text': text,
                          'createdAt': FieldValue.serverTimestamp(),
                        });
                        commentController.clear();
                        await createMarketplaceNotification(
                          toUserId: ownerId,
                          title: 'មាន Comment ថ្មី',
                          message: '${profile['name']} បាន comment លើ $postTitle',
                          type: 'comment',
                          referenceCollection: collectionName,
                          referenceId: documentId,
                        );
                      },
                      child: const Icon(Icons.send),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  commentController.dispose();
}

Future<void> showDealChatSheet(BuildContext context, DealRecord deal) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null || deal.documentId == null) {
    showMessage(context, 'សូមចូលគណនីជាមុនសិន');
    return;
  }
  final isParticipant = deal.buyerId == user.uid || deal.farmerId == user.uid;
  if (!isParticipant) {
    showMessage(context, 'Chat នេះសម្រាប់ដៃគូ Deal ប៉ុណ្ណោះ');
    return;
  }

  final messageController = TextEditingController();
  final dealRef = FirebaseFirestore.instance.collection('deals').doc(deal.documentId);
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.only(left: 16, right: 16, top: 8, bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16),
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.78,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${deal.crop} Deal Chat', style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.darkGreen)),
                const SizedBox(height: 8),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: dealRef.collection('messages').orderBy('createdAt', descending: true).snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: AppColors.green));
                      final messages = snapshot.data?.docs ?? [];
                      if (messages.isEmpty) return const Center(child: Text('Start chatting about this deal'));
                      return ListView.builder(
                        reverse: true,
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final data = messages[index].data();
                          final isMe = data['senderId'] == user.uid;
                          return Align(
                            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.all(10),
                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                              decoration: BoxDecoration(
                                color: isMe ? AppColors.green : AppColors.lightGreen,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                data['text']?.toString() ?? '',
                                style: GoogleFonts.notoSansKhmer(color: isMe ? Colors.white : AppColors.text),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: messageController,
                        decoration: const InputDecoration(labelText: 'Message'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () async {
                        final text = messageController.text.trim();
                        if (text.isEmpty) return;
                        final profile = await currentUserMarketplaceProfile(user);
                        await dealRef.collection('messages').add({
                          'senderId': user.uid,
                          'senderName': profile['name'],
                          'text': text,
                          'createdAt': FieldValue.serverTimestamp(),
                        });
                        await dealRef.set({'lastMessage': text, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
                        messageController.clear();
                        final otherUserId = user.uid == deal.buyerId ? deal.farmerId : deal.buyerId;
                        await createMarketplaceNotification(
                          toUserId: otherUserId,
                          title: 'មានសារថ្មីក្នុង Deal Chat',
                          message: '${profile['name']}: $text',
                          type: 'chat',
                          referenceCollection: 'deals',
                          referenceId: deal.documentId ?? '',
                        );
                      },
                      child: const Icon(Icons.send),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  messageController.dispose();
}

ImageProvider? imageProviderFromBase64OrUrl(String base64Value, String url) {
  final cleanBase64 = base64Value.trim();
  if (cleanBase64.isNotEmpty) {
    try {
      return MemoryImage(base64Decode(cleanBase64));
    } catch (_) {}
  }
  final cleanUrl = url.trim();
  if (cleanUrl.isNotEmpty) return NetworkImage(cleanUrl);
  return null;
}

String profileText(Map<String, dynamic> data, String key, String fallback) {
  final value = data[key]?.toString().trim() ?? '';
  return value.isEmpty ? fallback : value;
}

Future<Map<String, String>> currentUserMarketplaceProfile(User user) async {
  await ensureUserDocument(user);
  final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
  final data = doc.data() ?? <String, dynamic>{};
  return {
    'name': profileText(data, 'name', user.displayName ?? user.email?.split('@').first ?? 'KasiAI User'),
    'email': profileText(data, 'email', user.email ?? ''),
    'phone': profileText(data, 'phone', ''),
    'province': profileText(data, 'province', ''),
    'role': profileText(data, 'role', ''),
    'photoBase64': profileText(data, 'photoBase64', ''),
    'photoUrl': profileText(data, 'photoUrl', user.photoURL ?? ''),
  };
}

class DealRequestInput {
  const DealRequestInput({required this.quantity, required this.note});
  final double quantity;
  final String note;
}

Future<DealRequestInput?> showDealRequestDialog(
  BuildContext context, {
  required String title,
  required double maxQuantity,
  required double price,
}) async {
  final quantityController = TextEditingController(text: maxQuantity.toStringAsFixed(0));
  final noteController = TextEditingController();
  final result = await showDialog<DealRequestInput>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: quantityController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'ចំនួន kg', helperText: 'តម្លៃ: ${money(price)}/kg'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: noteController,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'សារទៅដៃគូ / លក្ខខណ្ឌ'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('បោះបង់')),
          FilledButton(
            onPressed: () {
              final qty = double.tryParse(quantityController.text.trim()) ?? 0;
              if (qty <= 0) return;
              Navigator.pop(dialogContext, DealRequestInput(quantity: qty, note: noteController.text.trim()));
            },
            child: const Text('បង្កើត Deal'),
          ),
        ],
      );
    },
  );
  quantityController.dispose();
  noteController.dispose();
  return result;
}

Future<void> showUserProfileSheet(
  BuildContext context, {
  required String userId,
  required String fallbackName,
  String fallbackEmail = '',
  String fallbackPhone = '',
  String fallbackProvince = '',
  String fallbackRole = '',
  String fallbackPhotoBase64 = '',
  String fallbackPhotoUrl = '',
}) async {
  final fallback = <String, dynamic>{
    'name': fallbackName,
    'email': fallbackEmail,
    'phone': fallbackPhone,
    'province': fallbackProvince,
    'role': fallbackRole,
    'photoBase64': fallbackPhotoBase64,
    'photoUrl': fallbackPhotoUrl,
  };

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      if (userId.trim().isEmpty) {
        return UserPublicProfileContent(data: fallback);
      }
      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').doc(userId).snapshots(),
        builder: (context, snapshot) {
          final data = <String, dynamic>{...fallback, ...?snapshot.data?.data()};
          return UserPublicProfileContent(data: data);
        },
      );
    },
  );
}


class UserPublicProfileContent extends StatelessWidget {
  const UserPublicProfileContent({super.key, required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final name = profileText(data, 'name', 'KasiAI User');
    final email = profileText(data, 'email', '');
    final phone = profileText(data, 'phone', '');
    final province = profileText(data, 'province', '');
    final role = profileText(data, 'role', '');
    final photoBase64 = profileText(data, 'photoBase64', '');
    final photoUrl = profileText(data, 'photoUrl', '');
    final imageProvider = imageProviderFromBase64OrUrl(photoBase64, photoUrl);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                onTap: imageProvider == null ? null : () => showFullImage(context, photoBase64, photoUrl),
                child: Container(
                  height: 230,
                  decoration: BoxDecoration(
                    color: AppColors.lightGreen,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: AppColors.border),
                    image: imageProvider == null ? null : DecorationImage(image: imageProvider, fit: BoxFit.cover),
                  ),
                  child: imageProvider == null ? const Icon(Icons.person_rounded, size: 72, color: AppColors.green) : null,
                ),
              ),
              const SizedBox(height: 14),
              Text(name, textAlign: TextAlign.center, style: GoogleFonts.notoSansKhmer(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.darkGreen)),
              if (role.isNotEmpty) Text(role, textAlign: TextAlign.center, style: GoogleFonts.notoSansKhmer(color: AppColors.green, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              if (email.isNotEmpty) InfoLine(label: 'Email', value: email),
              if (phone.isNotEmpty) InfoLine(label: 'Phone', value: phone),
              if (province.isNotEmpty) InfoLine(label: 'Province', value: province),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.check),
                label: const Text('OK'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> ensureUserDocument(User user, {String? name, String? photoUrl}) async {
  final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
  final snapshot = await docRef.get();
  final now = FieldValue.serverTimestamp();
  final displayName = (name ?? user.displayName ?? user.email?.split('@').first ?? 'KasiAI User').trim();

  if (snapshot.exists) {
    await docRef.set({
      'name': displayName,
      'email': user.email ?? '',
      'photoUrl': photoUrl ?? user.photoURL ?? '',
      'updatedAt': now,
    }, SetOptions(merge: true));
    return;
  }

  await docRef.set({
    'name': displayName,
    'email': user.email ?? '',
    'phone': '',
    'province': kCambodianProvinces.first,
    'role': kUserRoles.first,
    'photoUrl': photoUrl ?? user.photoURL ?? '',
    'photoBase64': '',
    'createdAt': now,
    'updatedAt': now,
  });
}

String formatDate(DateTime date) {
  return '${date.day}/${date.month}/${date.year}';
}

String money(double value) {
  return '\$${value.toStringAsFixed(2)}';
}

class DiseaseResult {
  const DiseaseResult({
    required this.disease,
    required this.severity,
    required this.confidence,
    required this.recommendation,
  });

  final String disease;
  final String severity;
  final double confidence;
  final String recommendation;
}


DateTime scanRecordDateFromMap(Map<String, dynamic> data) {
  final localValue = data['localCreatedAt'];
  if (localValue is Timestamp) return localValue.toDate();
  final createdValue = data['createdAt'];
  if (createdValue is Timestamp) return createdValue.toDate();
  return DateTime.fromMillisecondsSinceEpoch(0);
}

ScanRecord scanRecordFromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data() ?? <String, dynamic>{};
  double confidence = 0.65;
  final rawConfidence = data['confidence'];
  if (rawConfidence is num) {
    confidence = rawConfidence.toDouble().clamp(0.0, 1.0).toDouble();
  } else {
    confidence = double.tryParse(rawConfidence?.toString() ?? '')?.clamp(0.0, 1.0).toDouble() ?? 0.65;
  }

  return ScanRecord(
    crop: data['crop']?.toString() ?? 'មិនអាចកំណត់បាន',
    disease: data['disease']?.toString() ?? 'មិនអាចកំណត់បាន',
    severity: data['severity']?.toString() ?? 'មិនច្បាស់',
    confidence: confidence,
    recommendation: data['recommendation']?.toString() ?? '',
    createdAt: scanRecordDateFromMap(data),
  );
}

class ScanRecord {
  const ScanRecord({
    required this.crop,
    required this.disease,
    required this.severity,
    required this.confidence,
    required this.recommendation,
    required this.createdAt,
  });

  final String crop;
  final String disease;
  final String severity;
  final double confidence;
  final String recommendation;
  final DateTime createdAt;
}

class PlantingRecord {
  const PlantingRecord({
    required this.id,
    required this.crop,
    required this.province,
    required this.area,
    required this.expectedKg,
    required this.harvestDate,
    this.userId = '',
    this.documentId,
  });

  final int id;
  final String crop;
  final String province;
  final double area;
  final double expectedKg;
  final DateTime harvestDate;
  final String userId;
  final String? documentId;

  factory PlantingRecord.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final harvestValue = data['harvestDate'];
    final DateTime harvestDate = harvestValue is Timestamp ? harvestValue.toDate() : DateTime.now();

    double toDouble(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    return PlantingRecord(
      id: doc.id.hashCode.abs(),
      documentId: doc.id,
      userId: data['userId']?.toString() ?? '',
      crop: data['crop']?.toString() ?? 'មិនស្គាល់',
      province: data['province']?.toString() ?? 'មិនស្គាល់',
      area: toDouble(data['areaHa'] ?? data['area']),
      expectedKg: toDouble(data['expectedKg']),
      harvestDate: harvestDate,
    );
  }
}



class ProductListing {
  const ProductListing({
    required this.id,
    required this.crop,
    required this.province,
    required this.quantity,
    required this.unit,
    required this.price,
    required this.grade,
    required this.harvestDate,
    required this.farmerName,
    this.userId = '',
    this.userEmail = '',
    this.documentId,
    this.photoBase64 = '',
    this.description = '',
    this.farmerPhone = '',
    this.farmerProvince = '',
    this.farmerRole = '',
    this.farmerPhotoBase64 = '',
    this.farmerPhotoUrl = '',
    this.status = 'Active',
    this.active = true,
  });

  final int id;
  final String crop;
  final String province;
  final double quantity;
  final String unit;
  final double price;
  final String grade;
  final DateTime harvestDate;
  final String farmerName;
  final String userId;
  final String userEmail;
  final String? documentId;
  final String photoBase64;
  final String description;
  final String farmerPhone;
  final String farmerProvince;
  final String farmerRole;
  final String farmerPhotoBase64;
  final String farmerPhotoUrl;
  final String status;
  final bool active;

  bool get isVisibleInMarket => active && status != 'Completed' && status != 'Deleted';

  factory ProductListing.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final harvestValue = data['harvestDate'];
    final DateTime harvestDate = harvestValue is Timestamp ? harvestValue.toDate() : DateTime.now();

    double toDouble(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    return ProductListing(
      id: doc.id.hashCode.abs(),
      documentId: doc.id,
      userId: data['userId']?.toString() ?? data['farmerId']?.toString() ?? '',
      userEmail: data['userEmail']?.toString() ?? data['farmerEmail']?.toString() ?? '',
      crop: data['crop']?.toString() ?? 'មិនស្គាល់',
      province: data['province']?.toString() ?? 'មិនស្គាល់',
      quantity: toDouble(data['quantity']),
      unit: data['unit']?.toString() ?? 'kg',
      price: toDouble(data['price']),
      grade: data['grade']?.toString() ?? 'Grade A',
      harvestDate: harvestDate,
      farmerName: data['farmerName']?.toString() ?? data['userEmail']?.toString() ?? 'កសិករ',
      photoBase64: data['productPhotoBase64']?.toString() ?? data['photoBase64']?.toString() ?? '',
      description: data['description']?.toString() ?? '',
      farmerPhone: data['farmerPhone']?.toString() ?? '',
      farmerProvince: data['farmerProvince']?.toString() ?? '',
      farmerRole: data['farmerRole']?.toString() ?? '',
      farmerPhotoBase64: data['farmerPhotoBase64']?.toString() ?? '',
      farmerPhotoUrl: data['farmerPhotoUrl']?.toString() ?? '',
      status: data['status']?.toString() ?? 'Active',
      active: data['active'] is bool ? data['active'] as bool : true,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'userEmail': userEmail,
      'farmerId': userId,
      'farmerEmail': userEmail,
      'crop': crop,
      'province': province,
      'quantity': quantity,
      'unit': unit,
      'price': price,
      'grade': grade,
      'harvestDate': Timestamp.fromDate(harvestDate),
      'farmerName': farmerName,
      'productPhotoBase64': photoBase64,
      'description': description,
      'active': active,
      'status': status,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

class BuyingDemand {
  const BuyingDemand({
    required this.id,
    required this.crop,
    required this.province,
    required this.quantity,
    required this.unit,
    required this.targetPrice,
    required this.buyerName,
    required this.deliveryDate,
    this.userId = '',
    this.userEmail = '',
    this.documentId,
    this.description = '',
    this.buyerPhone = '',
    this.buyerProvince = '',
    this.buyerRole = '',
    this.buyerPhotoBase64 = '',
    this.buyerPhotoUrl = '',
    this.status = 'Active',
    this.active = true,
  });

  final int id;
  final String crop;
  final String province;
  final double quantity;
  final String unit;
  final double targetPrice;
  final String buyerName;
  final DateTime deliveryDate;
  final String userId;
  final String userEmail;
  final String? documentId;
  final String description;
  final String buyerPhone;
  final String buyerProvince;
  final String buyerRole;
  final String buyerPhotoBase64;
  final String buyerPhotoUrl;
  final String status;
  final bool active;

  bool get isVisibleInMarket => active && status != 'Completed' && status != 'Deleted';

  factory BuyingDemand.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final deliveryValue = data['deliveryDate'];
    final DateTime deliveryDate = deliveryValue is Timestamp ? deliveryValue.toDate() : DateTime.now();

    double toDouble(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    return BuyingDemand(
      id: doc.id.hashCode.abs(),
      documentId: doc.id,
      userId: data['userId']?.toString() ?? data['buyerId']?.toString() ?? '',
      userEmail: data['userEmail']?.toString() ?? data['buyerEmail']?.toString() ?? '',
      crop: data['crop']?.toString() ?? 'មិនស្គាល់',
      province: data['province']?.toString() ?? 'មិនស្គាល់',
      quantity: toDouble(data['quantity']),
      unit: data['unit']?.toString() ?? 'kg',
      targetPrice: toDouble(data['targetPrice'] ?? data['price']),
      buyerName: data['buyerName']?.toString() ?? data['userEmail']?.toString() ?? 'អ្នកទិញ',
      deliveryDate: deliveryDate,
      description: data['description']?.toString() ?? '',
      buyerPhone: data['buyerPhone']?.toString() ?? '',
      buyerProvince: data['buyerProvince']?.toString() ?? '',
      buyerRole: data['buyerRole']?.toString() ?? '',
      buyerPhotoBase64: data['buyerPhotoBase64']?.toString() ?? '',
      buyerPhotoUrl: data['buyerPhotoUrl']?.toString() ?? '',
      status: data['status']?.toString() ?? 'Active',
      active: data['active'] is bool ? data['active'] as bool : true,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'userEmail': userEmail,
      'buyerId': userId,
      'buyerEmail': userEmail,
      'crop': crop,
      'province': province,
      'quantity': quantity,
      'unit': unit,
      'targetPrice': targetPrice,
      'buyerName': buyerName,
      'description': description,
      'deliveryDate': Timestamp.fromDate(deliveryDate),
      'active': active,
      'status': status,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

class DealRecord {
  const DealRecord({
    required this.id,
    required this.crop,
    required this.buyerName,
    required this.farmerName,
    required this.quantity,
    required this.value,
    required this.commission,
    required this.status,
    this.documentId,
    this.buyerId = '',
    this.buyerEmail = '',
    this.buyerPhone = '',
    this.buyerProvince = '',
    this.buyerRole = '',
    this.buyerPhotoBase64 = '',
    this.buyerPhotoUrl = '',
    this.farmerId = '',
    this.farmerEmail = '',
    this.farmerPhone = '',
    this.farmerProvince = '',
    this.farmerRole = '',
    this.farmerPhotoBase64 = '',
    this.farmerPhotoUrl = '',
    this.productPhotoBase64 = '',
    this.note = '',
    this.productId = '',
    this.demandId = '',
  });

  final int id;
  final String crop;
  final String buyerName;
  final String farmerName;
  final double quantity;
  final double value;
  final double commission;
  final String status;
  final String? documentId;
  final String buyerId;
  final String buyerEmail;
  final String buyerPhone;
  final String buyerProvince;
  final String buyerRole;
  final String buyerPhotoBase64;
  final String buyerPhotoUrl;
  final String farmerId;
  final String farmerEmail;
  final String farmerPhone;
  final String farmerProvince;
  final String farmerRole;
  final String farmerPhotoBase64;
  final String farmerPhotoUrl;
  final String productPhotoBase64;
  final String note;
  final String productId;
  final String demandId;

  factory DealRecord.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};

    double toDouble(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    return DealRecord(
      id: doc.id.hashCode.abs(),
      documentId: doc.id,
      crop: data['crop']?.toString() ?? 'មិនស្គាល់',
      buyerName: data['buyerName']?.toString() ?? 'អ្នកទិញ',
      farmerName: data['farmerName']?.toString() ?? 'កសិករ',
      quantity: toDouble(data['quantity']),
      value: toDouble(data['value']),
      commission: toDouble(data['commission']),
      status: data['status']?.toString() ?? 'Pending',
      buyerId: data['buyerId']?.toString() ?? '',
      buyerEmail: data['buyerEmail']?.toString() ?? '',
      buyerPhone: data['buyerPhone']?.toString() ?? '',
      buyerProvince: data['buyerProvince']?.toString() ?? '',
      buyerRole: data['buyerRole']?.toString() ?? '',
      buyerPhotoBase64: data['buyerPhotoBase64']?.toString() ?? '',
      buyerPhotoUrl: data['buyerPhotoUrl']?.toString() ?? '',
      farmerId: data['farmerId']?.toString() ?? '',
      farmerEmail: data['farmerEmail']?.toString() ?? '',
      farmerPhone: data['farmerPhone']?.toString() ?? '',
      farmerProvince: data['farmerProvince']?.toString() ?? '',
      farmerRole: data['farmerRole']?.toString() ?? '',
      farmerPhotoBase64: data['farmerPhotoBase64']?.toString() ?? '',
      farmerPhotoUrl: data['farmerPhotoUrl']?.toString() ?? '',
      productPhotoBase64: data['productPhotoBase64']?.toString() ?? '',
      note: data['note']?.toString() ?? '',
      productId: data['productId']?.toString() ?? '',
      demandId: data['demandId']?.toString() ?? '',
    );
  }
}

class ProfitRecord {
  const ProfitRecord({required this.title, required this.type, required this.amount});

  final String title;
  final ProfitType type;
  final double amount;
}

enum ProfitType { expense, income }

class MarketPrice {
  const MarketPrice({required this.crop, required this.price, required this.trend});

  final String crop;
  final double price;
  final String trend;
}
