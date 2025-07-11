import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../services/auth_service.dart';
import '../services/friends_service.dart';
import '../screens/pollution_tracker_screen.dart';
import '../screens/food_locator.dart';
import '../widgets/modern_bottom_nav.dart';


class EcoChallengesScreen extends StatefulWidget {
  @override
  _EcoChallengesScreenState createState() => _EcoChallengesScreenState();
}

class _EcoChallengesScreenState extends State<EcoChallengesScreen> {
  final AuthService _authService = AuthService();
  final FriendsService _friendsService = FriendsService();
  DatabaseReference? _database;
  Map<String, bool> _completedChallenges = {};
  int _totalPoints = 0;
  bool _isLoading = true;
  List<Map<String, dynamic>> _friendsLeaderboard = [];
  bool _showLeaderboard = false;
  String _selectedCategory = 'All';
  int _currentIndex = 1;

  // Colors
  static const Color greenColor = Color(0xFF00A74C);

  // Add category list
  final List<String> _categories = [
    'All',
    'Shopping',
    'Waste Reduction',
    'Transportation',
    'Local Support',
    'Nutrition',
    'Growing',
    'Community',
    'Energy',
    'Water',
    'Education',
  ];

  final List<Map<String, dynamic>> _challenges = [
    {
      'id': 'bring_reusable_bag',
      'title': 'Bring Your Own Bag',
      'description': 'Use a reusable bag when shopping for food',
      'points': 10,
      'icon': Icons.shopping_bag,
      'color': Colors.green,
      'category': 'Shopping',
    },
    {
      'id': 'zero_food_waste',
      'title': 'Zero Food Waste Day',
      'description': 'Complete a day without throwing away any food',
      'points': 20,
      'icon': Icons.restaurant,
      'color': Colors.orange,
      'category': 'Waste Reduction',
    },
    {
      'id': 'walk_to_food',
      'title': 'Walk to Food',
      'description': 'Walk or bike to get your food instead of driving',
      'points': 15,
      'icon': Icons.directions_walk,
      'color': Colors.blue,
      'category': 'Transportation',
    },
    {
      'id': 'local_food',
      'title': 'Local Food Hero',
      'description': 'Buy food from a local farmer\'s market or local business',
      'points': 25,
      'icon': Icons.store,
      'color': Colors.purple,
      'category': 'Local Support',
    },
    {
      'id': 'plant_based_meal',
      'title': 'Plant-Based Meal',
      'description': 'Enjoy a completely plant-based meal',
      'points': 15,
      'icon': Icons.eco,
      'color': Colors.lightGreen,
      'category': 'Nutrition',
    },
    {
      'id': 'compost_scraps',
      'title': 'Compost Champion',
      'description': 'Compost your food scraps instead of throwing them away',
      'points': 20,
      'icon': Icons.recycling,
      'color': Colors.brown,
      'category': 'Waste Reduction',
    },
    {
      'id': 'reusable_container',
      'title': 'Container Crusader',
      'description': 'Use a reusable container for takeout or leftovers',
      'points': 10,
      'icon': Icons.lunch_dining,
      'color': Colors.teal,
      'category': 'Waste Reduction',
    },
    {
      'id': 'grow_herbs',
      'title': 'Herb Garden Starter',
      'description': 'Start growing your own herbs at home',
      'points': 30,
      'icon': Icons.local_florist,
      'color': Colors.green,
      'category': 'Growing',
    },
    {
      'id': 'bulk_shopping',
      'title': 'Bulk Buyer',
      'description': 'Buy food in bulk to reduce packaging waste',
      'points': 15,
      'icon': Icons.scale,
      'color': Colors.amber,
      'category': 'Shopping',
    },
    {
      'id': 'share_leftovers',
      'title': 'Leftover Sharer',
      'description': 'Share leftover food with friends, family, or community',
      'points': 25,
      'icon': Icons.share,
      'color': Colors.pink,
      'category': 'Community',
    },
    {
      'id': 'meatless_monday',
      'title': 'Meatless Monday',
      'description': 'Go meat-free for an entire Monday',
      'points': 20,
      'icon': Icons.no_food,
      'color': Colors.red,
      'category': 'Nutrition',
    },
    {
      'id': 'food_rescue',
      'title': 'Food Rescue Volunteer',
      'description': 'Volunteer at a food rescue organization or food bank',
      'points': 50,
      'icon': Icons.volunteer_activism,
      'color': Colors.deepPurple,
      'category': 'Community',
    },
    {
      'id': 'plastic_free_week',
      'title': 'Plastic-Free Week',
      'description': 'Complete a week without buying any plastic-packaged food',
      'points': 50,
      'icon': Icons.delete_outline,
      'color': Colors.green,
      'category': 'Shopping',
    },
    {
      'id': 'seasonal_shopping',
      'title': 'Seasonal Shopper',
      'description': 'Buy only seasonal produce for a week',
      'points': 30,
      'icon': Icons.calendar_today,
      'color': Colors.green,
      'category': 'Shopping',
    },
    {
      'id': 'package_free',
      'title': 'Package-Free Pioneer',
      'description': 'Buy food from a package-free store',
      'points': 25,
      'icon': Icons.inventory_2,
      'color': Colors.green,
      'category': 'Shopping',
    },
    {
      'id': 'zero_waste_week',
      'title': 'Zero Waste Week',
      'description': 'Generate no food waste for an entire week',
      'points': 75,
      'icon': Icons.delete_sweep,
      'color': Colors.orange,
      'category': 'Waste Reduction',
    },
    {
      'id': 'food_scrap_art',
      'title': 'Food Scrap Artist',
      'description': 'Create art or crafts from food scraps',
      'points': 35,
      'icon': Icons.brush,
      'color': Colors.orange,
      'category': 'Waste Reduction',
    },
    {
      'id': 'reuse_containers',
      'title': 'Container Reuse Master',
      'description': 'Reuse food containers for 10 different purposes',
      'points': 40,
      'icon': Icons.recycling,
      'color': Colors.orange,
      'category': 'Waste Reduction',
    },
    {
      'id': 'bike_grocery',
      'title': 'Bike Grocery Run',
      'description': 'Use a bicycle for all grocery shopping for a week',
      'points': 45,
      'icon': Icons.pedal_bike,
      'color': Colors.blue,
      'category': 'Transportation',
    },
    {
      'id': 'public_transport_food',
      'title': 'Public Transport Foodie',
      'description': 'Use public transport for all food shopping for a week',
      'points': 30,
      'icon': Icons.directions_bus,
      'color': Colors.blue,
      'category': 'Transportation',
    },
    {
      'id': 'walking_distance',
      'title': 'Walking Distance Warrior',
      'description': 'Only shop at food stores within walking distance for a week',
      'points': 35,
      'icon': Icons.directions_walk,
      'color': Colors.blue,
      'category': 'Transportation',
    },
    {
      'id': 'farm_visit',
      'title': 'Farm Visitor',
      'description': 'Visit a local farm and buy directly from them',
      'points': 40,
      'icon': Icons.agriculture,
      'color': Colors.purple,
      'category': 'Local Support',
    },
    {
      'id': 'local_restaurant',
      'title': 'Local Restaurant Explorer',
      'description': 'Try 5 different local restaurants that source local ingredients',
      'points': 50,
      'icon': Icons.restaurant,
      'color': Colors.purple,
      'category': 'Local Support',
    },
    {
      'id': 'food_coop',
      'title': 'Food Co-op Member',
      'description': 'Join a local food co-op and make your first purchase',
      'points': 35,
      'icon': Icons.group_work,
      'color': Colors.purple,
      'category': 'Local Support',
    },
    {
      'id': 'plant_based_week',
      'title': 'Plant-Based Week',
      'description': 'Eat only plant-based meals for a week',
      'points': 60,
      'icon': Icons.eco,
      'color': Colors.lightGreen,
      'category': 'Nutrition',
    },
    {
      'id': 'seasonal_diet',
      'title': 'Seasonal Diet',
      'description': 'Eat only seasonal foods for a week',
      'points': 40,
      'icon': Icons.calendar_month,
      'color': Colors.lightGreen,
      'category': 'Nutrition',
    },
    {
      'id': 'whole_foods',
      'title': 'Whole Foods Week',
      'description': 'Eat only whole, unprocessed foods for a week',
      'points': 45,
      'icon': Icons.spa,
      'color': Colors.lightGreen,
      'category': 'Nutrition',
    },
    {
      'id': 'vegetable_garden',
      'title': 'Vegetable Garden',
      'description': 'Start and maintain a vegetable garden',
      'points': 75,
      'icon': Icons.park,
      'color': Colors.green,
      'category': 'Growing',
    },
    {
      'id': 'indoor_herbs',
      'title': 'Indoor Herb Master',
      'description': 'Grow 5 different herbs indoors',
      'points': 40,
      'icon': Icons.window,
      'color': Colors.green,
      'category': 'Growing',
    },
    {
      'id': 'seed_saving',
      'title': 'Seed Saver',
      'description': 'Save seeds from 3 different plants',
      'points': 30,
      'icon': Icons.grass,
      'color': Colors.green,
      'category': 'Growing',
    },
    {
      'id': 'food_swap',
      'title': 'Food Swap Organizer',
      'description': 'Organize a community food swap event',
      'points': 60,
      'icon': Icons.swap_horiz,
      'color': Colors.pink,
      'category': 'Community',
    },
    {
      'id': 'cooking_class',
      'title': 'Sustainable Cooking Teacher',
      'description': 'Teach a sustainable cooking class',
      'points': 55,
      'icon': Icons.school,
      'color': Colors.pink,
      'category': 'Community',
    },
    {
      'id': 'community_garden',
      'title': 'Community Gardener',
      'description': 'Participate in a community garden project',
      'points': 45,
      'icon': Icons.people,
      'color': Colors.pink,
      'category': 'Community',
    },
    {
      'id': 'solar_cooking',
      'title': 'Solar Cooker',
      'description': 'Cook a meal using solar energy',
      'points': 40,
      'icon': Icons.wb_sunny,
      'color': Colors.amber,
      'category': 'Energy',
    },
    {
      'id': 'energy_efficient',
      'title': 'Energy-Efficient Chef',
      'description': 'Use energy-efficient cooking methods for a week',
      'points': 35,
      'icon': Icons.electric_bolt,
      'color': Colors.amber,
      'category': 'Energy',
    },
    {
      'id': 'batch_cooking',
      'title': 'Batch Cooking Master',
      'description': 'Cook multiple meals at once to save energy',
      'points': 30,
      'icon': Icons.restaurant_menu,
      'color': Colors.amber,
      'category': 'Energy',
    },
    {
      'id': 'water_saving_cook',
      'title': 'Water-Saving Cook',
      'description': 'Reduce water usage in cooking by 50% for a week',
      'points': 35,
      'icon': Icons.water_drop,
      'color': Colors.blue,
      'category': 'Water',
    },
    {
      'id': 'rainwater_garden',
      'title': 'Rainwater Gardener',
      'description': 'Use collected rainwater for your garden',
      'points': 40,
      'icon': Icons.water,
      'color': Colors.blue,
      'category': 'Water',
    },
    {
      'id': 'water_reuse',
      'title': 'Water Reuse Expert',
      'description': 'Reuse cooking water for plants or cleaning',
      'points': 25,
      'icon': Icons.recycling,
      'color': Colors.blue,
      'category': 'Water',
    },
    {
      'id': 'food_waste_workshop',
      'title': 'Food Waste Workshop',
      'description': 'Attend a workshop on reducing food waste',
      'points': 30,
      'icon': Icons.school,
      'color': Colors.indigo,
      'category': 'Education',
    },
    {
      'id': 'sustainable_cooking',
      'title': 'Sustainable Cooking Course',
      'description': 'Complete an online course on sustainable cooking',
      'points': 45,
      'icon': Icons.menu_book,
      'color': Colors.indigo,
      'category': 'Education',
    },
    {
      'id': 'food_system',
      'title': 'Food System Student',
      'description': 'Learn about local food systems and share knowledge',
      'points': 35,
      'icon': Icons.lightbulb,
      'color': Colors.indigo,
      'category': 'Education',
    },
  ];

  String get _currentUserId => _authService.currentUserId ?? 'unknown';
  String get _currentUserName => _authService.currentUserDisplayName;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    setState(() => _isLoading = true);
    try {
      await _initializeDatabase();
      await _loadUserProgress();
      await _loadFriendsLeaderboard();
    } catch (e) {
      print('Error initializing app: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _initializeDatabase() async {
    try {
      _database = FirebaseDatabase.instance.ref();
    } catch (e) {
      print('Failed to initialize database: $e');
    }
  }

  Future<void> _loadUserProgress() async {
    if (_database == null) return;
    try {
      final snapshot = await _database!
          .child('userChallenges')
          .child(_currentUserId)
          .get();

      if (snapshot.exists) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        setState(() {
          _completedChallenges = Map<String, bool>.from(data['completed'] ?? {});
          _totalPoints = data['totalPoints'] ?? 0;
        });
      }
    } catch (e) {
      print('Failed to load user progress: $e');
    }
  }

  Future<void> _completeChallenge(String challengeId, int points) async {
    if (_completedChallenges[challengeId] == true) return;
    setState(() {
      _completedChallenges[challengeId] = true;
      _totalPoints += points;
    });
    if (_database != null) {
      try {
        await _database!
            .child('userChallenges')
            .child(_currentUserId)
            .update({
          'completed': _completedChallenges,
          'totalPoints': _totalPoints,
          'lastUpdated': ServerValue.timestamp,
        });
        _showSnackBar('Challenge completed! +$points points', greenColor);
      } catch (e) {
        _showSnackBar('Challenge completed locally!', Colors.orange);
      }
    } else {
      _showSnackBar('Challenge completed locally!', Colors.orange);
    }
  }

  Future<void> _resetProgress() async {
    final shouldReset = await _showResetDialog();
    if (shouldReset != true) return;
    setState(() {
      _completedChallenges.clear();
      _totalPoints = 0;
    });
    if (_database != null) {
      try {
        await _database!
            .child('userChallenges')
            .child(_currentUserId)
            .remove();
        _showSnackBar('Progress reset successfully!', greenColor);
      } catch (e) {
        _showSnackBar('Progress reset locally!', Colors.orange);
      }
    } else {
      _showSnackBar('Progress reset locally!', Colors.orange);
    }
  }

  Future<bool?> _showResetDialog() async {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.refresh, color: Colors.orange),
              SizedBox(width: 8),
              Text('Reset Progress'),
            ],
          ),
          content: Text(
            'Are you sure you want to reset all your challenge progress? '
            'This will remove all completed challenges and reset your points to 0.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: Text('Reset'),
            ),
          ],
        );
      },
    );
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: Duration(seconds: 2),
      ),
    );
  }

  String _getUserLevel() {
    if (_totalPoints >= 200) return 'Eco Champion';
    if (_totalPoints >= 150) return 'Green Guardian';
    if (_totalPoints >= 100) return 'Earth Protector';
    if (_totalPoints >= 50) return 'Eco Warrior';
    if (_totalPoints >= 25) return 'Green Beginner';
    return 'Eco Newbie';
  }

  Color _getUserLevelColor() {
    if (_totalPoints >= 200) return Colors.amber[700]!;
    if (_totalPoints >= 150) return Colors.purple;
    if (_totalPoints >= 100) return Colors.blue;
    if (_totalPoints >= 50) return Colors.green;
    if (_totalPoints >= 25) return Colors.orange;
    return Colors.grey;
  }

  int _getCompletedCount() {
    return _completedChallenges.values.where((completed) => completed).length;
  }

  Future<void> _loadFriendsLeaderboard() async {
    if (_database == null) return;
    try {
      final friendsStream = _friendsService.getFriends();
      final friendsSnapshot = await friendsStream.first;
      List<Map<String, dynamic>> leaderboardData = [];
      leaderboardData.add({
        'userId': _currentUserId,
        'userName': _currentUserName,
        'points': _totalPoints,
        'completedChallenges': _getCompletedCount(),
        'isCurrentUser': true,
        'level': _getUserLevel(),
        'levelColor': _getUserLevelColor(),
      });

      for (var friend in friendsSnapshot) {
        final friendId = friend['userId'];
        final friendName = friend['userName'];
        if (friendId == null || friendName == null) continue;
        try {
          final friendChallengesSnapshot = await _database!
              .child('userChallenges')
              .child(friendId)
              .get();
          int friendPoints = 0;
          int friendCompletedCount = 0;
          if (friendChallengesSnapshot.exists) {
            final friendData = Map<String, dynamic>.from(friendChallengesSnapshot.value as Map);
            friendPoints = friendData['totalPoints'] ?? 0;
            final completedChallenges = Map<String, bool>.from(friendData['completed'] ?? {});
            friendCompletedCount = completedChallenges.values.where((completed) => completed).length;
          }
          leaderboardData.add({
            'userId': friendId,
            'userName': friendName,
            'points': friendPoints,
            'completedChallenges': friendCompletedCount,
            'isCurrentUser': false,
            'level': _getUserLevelFromPoints(friendPoints),
            'levelColor': _getUserLevelColorFromPoints(friendPoints),
          });
        } catch (e) {
          continue;
        }
      }
      leaderboardData.sort((a, b) => b['points'].compareTo(a['points']));
      for (int i = 0; i < leaderboardData.length; i++) {
        leaderboardData[i]['rank'] = i + 1;
      }
      if (mounted) {
        setState(() {
          _friendsLeaderboard = leaderboardData;
        });
      }
    } catch (e) {}
  }

  String _getUserLevelFromPoints(int points) {
    if (points >= 200) return 'Eco Champion';
    if (points >= 150) return 'Green Guardian';
    if (points >= 100) return 'Earth Protector';
    if (points >= 50) return 'Eco Warrior';
    if (points >= 25) return 'Green Beginner';
    return 'Eco Newbie';
  }

  Color _getUserLevelColorFromPoints(int points) {
    if (points >= 200) return Colors.amber[700]!;
    if (points >= 150) return Colors.purple;
    if (points >= 100) return Colors.blue;
    if (points >= 50) return Colors.green;
    if (points >= 25) return Colors.orange;
    return Colors.grey;
  }

  void _toggleLeaderboard() {
    setState(() {
      _showLeaderboard = !_showLeaderboard;
    });
    if (_showLeaderboard) {
      _loadFriendsLeaderboard();
    }
  }

  void _onNavTap(int index) {
    if (index == _currentIndex) return;
    
    switch (index) {
      case 0:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => FoodLocatorScreen(),
          ),
        );
        break;
      case 1:
        // Already on Eco Challenges
        break;
      case 2:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => PollutionTrackerScreen(),
          ),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 2,
          title: Row(
            children: [
              Icon(Icons.eco, color: greenColor),
              SizedBox(width: 8),
              Text('Eco Challenges', style: TextStyle(color: greenColor, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: greenColor),
              SizedBox(height: 16),
              Text('Loading your eco journey...'),
            ],
          ),
        ),
        bottomNavigationBar: ModernBottomNav(
          currentIndex: _currentIndex,
          onTap: _onNavTap,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 2,
        title: Row(
          children: [
            Icon(Icons.eco, color: greenColor),
            SizedBox(width: 8),
            Text('Eco Challenges', style: TextStyle(color: greenColor, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.leaderboard, color: greenColor),
            onPressed: _toggleLeaderboard,
            tooltip: 'Friends Leaderboard',
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.grey[700]),
            onPressed: _resetProgress,
            tooltip: 'Reset Progress',
          ),
        ],
      ),
      body: Column(
        children: [
          // Progress Header
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [greenColor.withOpacity(0.9), greenColor],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatCard(
                      'Total Points',
                      _totalPoints.toString(),
                      Icons.stars,
                      Colors.amber,
                    ),
                    _buildStatCard(
                      'Completed',
                      '${_getCompletedCount()}/${_challenges.length}',
                      Icons.check_circle,
                      Colors.white,
                    ),
                  ],
                ),
                SizedBox(height: 16),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: _getUserLevelColor(),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.eco, color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Text(
                        _getUserLevel(),
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Challenges List or Leaderboard
          Expanded(
            child: _showLeaderboard ? _buildLeaderboard() : _buildChallengesList(),
          ),
        ],
      ),
      bottomNavigationBar: ModernBottomNav(
        currentIndex: _currentIndex,
        onTap: _onNavTap,
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChallengesList() {
    // Filter challenges based on selected category
    final filteredChallenges = _selectedCategory == 'All'
        ? _challenges
        : _challenges.where((challenge) => challenge['category'] == _selectedCategory).toList();

    return Column(
      children: [
        // Category Filter
        Container(
          height: 50,
          margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _categories.length,
            itemBuilder: (context, index) {
              final category = _categories[index];
              final isSelected = category == _selectedCategory;
              return Padding(
                padding: EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(category),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _selectedCategory = category;
                      });
                    }
                  },
                  backgroundColor: Colors.grey[200],
                  selectedColor: greenColor.withOpacity(0.2),
                  labelStyle: TextStyle(
                    color: isSelected ? greenColor : Colors.grey[700],
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              );
            },
          ),
        ),
        // Challenges List
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.all(16),
            itemCount: filteredChallenges.length,
            itemBuilder: (context, index) {
              final challenge = filteredChallenges[index];
              final isCompleted = _completedChallenges[challenge['id']] == true;

              return Card(
                margin: EdgeInsets.only(bottom: 12),
                elevation: 2,
                child: ListTile(
                  contentPadding: EdgeInsets.all(16),
                  leading: Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isCompleted 
                          ? Colors.grey[300] 
                          : challenge['color'].withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      challenge['icon'],
                      color: isCompleted 
                          ? Colors.grey[600] 
                          : challenge['color'],
                      size: 24,
                    ),
                  ),
                  title: Text(
                    challenge['title'],
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      decoration: isCompleted 
                          ? TextDecoration.lineThrough 
                          : null,
                      color: isCompleted ? Colors.grey[600] : null,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: 4),
                      Text(
                        challenge['description'],
                        style: TextStyle(
                          color: isCompleted ? Colors.grey[600] : null,
                        ),
                      ),
                      SizedBox(height: 8),
                      Row(
                        children: [
                          // Category Chip
                          Flexible(
                            child: Container(
                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: challenge['color'].withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                challenge['category'],
                                style: TextStyle(
                                  color: challenge['color'],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                maxLines: 1,
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          // Points Label
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.star, color: Colors.amber, size: 16),
                              SizedBox(width: 4),
                              Text(
                                '${challenge['points']} pts',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber[700],
                                  overflow: TextOverflow.ellipsis,
                                ),
                                maxLines: 1,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                  trailing: isCompleted
                      ? Icon(
                          Icons.check_circle,
                          color: greenColor,
                          size: 28,
                        )
                      : ElevatedButton(
                          onPressed: () => _completeChallenge(
                            challenge['id'],
                            challenge['points'],
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: greenColor,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                          ),
                          child: Text('Complete'),
                        ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLeaderboard() {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: greenColor.withOpacity(0.1),
            border: Border(
              bottom: BorderSide(color: greenColor.withOpacity(0.25), width: 1),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.leaderboard, color: greenColor, size: 24),
              SizedBox(width: 8),
              Text(
                'Friends Leaderboard',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: greenColor,
                ),
              ),
              Spacer(),
              TextButton.icon(
                onPressed: () {
                  _loadFriendsLeaderboard();
                  _showSnackBar('Refreshing leaderboard...', Colors.blue);
                },
                icon: Icon(Icons.refresh, size: 16, color: greenColor),
                label: Text('Refresh', style: TextStyle(color: greenColor)),
                style: TextButton.styleFrom(
                  foregroundColor: greenColor,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _friendsLeaderboard.length <= 1 ? _buildEmptyLeaderboard() : _buildLeaderboardList(),
        ),
      ],
    );
  }

  Widget _buildEmptyLeaderboard() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
            SizedBox(height: 16),
            Text(
              'No Friends Yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Add friends to see how you compare on eco challenges!',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _toggleLeaderboard(),
              icon: Icon(Icons.list),
              label: Text('View Challenges'),
              style: ElevatedButton.styleFrom(
                backgroundColor: greenColor,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeaderboardList() {
    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: _friendsLeaderboard.length,
      itemBuilder: (context, index) {
        final user = _friendsLeaderboard[index];
        final isCurrentUser = user['isCurrentUser'] == true;
        final rank = user['rank'];
        return Card(
          margin: EdgeInsets.only(bottom: 8),
          elevation: isCurrentUser ? 4 : 1,
          color: isCurrentUser ? greenColor.withOpacity(0.1) : Colors.white,
          child: ListTile(
            contentPadding: EdgeInsets.all(16),
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Rank badge
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _getRankColor(rank),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(
                      '#$rank',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                // User avatar
                CircleAvatar(
                  backgroundColor: user['levelColor'],
                  child: Text(
                    user['userName'][0].toUpperCase(),
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    isCurrentUser ? '${user['userName']} (You)' : user['userName'],
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isCurrentUser ? greenColor : Colors.black87,
                    ),
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: user['levelColor'].withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    user['level'],
                    style: TextStyle(
                      color: user['levelColor'],
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Row(
  children: [
    Icon(Icons.star, color: Colors.amber, size: 16),
    SizedBox(width: 4),
    Flexible(
      child: Text(
        '${user['points']} points',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: Colors.amber[700],
        ),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
    ),
    SizedBox(width: 12),
    Icon(Icons.check_circle, color: greenColor, size: 16),
    SizedBox(width: 4),
    Flexible(
      child: Text(
        '${user['completedChallenges']} completed',
        style: TextStyle(
          color: greenColor,
        ),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
    ),
  ],
),

            trailing: rank <= 3 ? _buildRankBadge(rank) : null,
          ),
        );
      },
    );
  }

  Color _getRankColor(int rank) {
    switch (rank) {
      case 1: return Colors.amber[600]!;
      case 2: return Colors.grey[400]!;
      case 3: return Colors.orange[700]!;
      default: return Colors.blue[600]!;
    }
  }

  Widget? _buildRankBadge(int rank) {
    IconData icon;
    Color color;
    switch (rank) {
      case 1:
        icon = Icons.emoji_events;
        color = Colors.amber[600]!;
        break;
      case 2:
        icon = Icons.emoji_events;
        color = Colors.grey[400]!;
        break;
      case 3:
        icon = Icons.emoji_events;
        color = Colors.orange[700]!;
        break;
      default:
        return null;
    }
    return Icon(icon, color: color, size: 28);
  }
}
