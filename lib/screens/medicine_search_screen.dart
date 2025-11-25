import 'package:flutter/material.dart';
import '../models/medicine.dart';
import 'medicine_detail_screen.dart';
import '../services/medicine_service.dart';
import 'dart:async';
import 'package:shimmer/shimmer.dart';

class MedicineSearchScreen extends StatefulWidget {
  final List<FoodDrugInteraction>? interactions;

  const MedicineSearchScreen({Key? key, this.interactions}) : super(key: key);

  @override
  _MedicineSearchScreenState createState() => _MedicineSearchScreenState();
}

class _MedicineSearchScreenState extends State<MedicineSearchScreen> with SingleTickerProviderStateMixin {
  List<FoodDrugInteraction> _allInteractions = [];
  List<FoodDrugInteraction> _filteredInteractions = [];
  bool _isLoading = true;
  bool _isSearching = false;
  
  // Search functionality
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _debounceTimer;

  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 400),
    );
    _loadInteractions();
    
    // Add listener to search controller for real-time search with debouncing
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _animationController.dispose();
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    // Cancel previous timer
    _debounceTimer?.cancel();
    
    // Set new timer for debouncing
    _debounceTimer = Timer(Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _searchQuery = _searchController.text.trim().toLowerCase();
          _filterInteractions();
        });
      }
    });
  }

  void _filterInteractions() {
    if (_searchQuery.isEmpty) {
      _filteredInteractions = List.from(_allInteractions);
      // Sort alphabetically by drug name when no search query
      _filteredInteractions.sort((a, b) {
        final nameA = (a.drugName ?? '').trim().toLowerCase();
        final nameB = (b.drugName ?? '').trim().toLowerCase();
        return nameA.compareTo(nameB);
      });
    } else {
      _filteredInteractions = _allInteractions.where((interaction) {
        final query = _searchQuery.toLowerCase();
        
        // Check multiple fields for better search results
        return interaction.drugName.toLowerCase().contains(query) ||
               interaction.foodToAvoid.toLowerCase().contains(query) ||
               interaction.description.toLowerCase().contains(query) ||
               interaction.searchKey.toLowerCase().contains(query) ||
               interaction.foodToTake.toLowerCase().contains(query) ||
               interaction.interactingWith.toLowerCase().contains(query) ||
               interaction.timeToTake.toLowerCase().contains(query);
      }).toList();
      
      // Sort results by relevance (exact matches first, then partial matches)
      _filteredInteractions.sort((a, b) {
        final aScore = _calculateRelevanceScore(a, _searchQuery);
        final bScore = _calculateRelevanceScore(b, _searchQuery);
        return bScore.compareTo(aScore); // Higher score first
      });
    }
  }

  int _calculateRelevanceScore(FoodDrugInteraction interaction, String query) {
    int score = 0;
    final queryLower = query.toLowerCase();
    
    // Exact matches get higher scores
    if (interaction.drugName.toLowerCase() == queryLower) score += 100;
    if (interaction.foodToAvoid.toLowerCase() == queryLower) score += 80;
    if (interaction.searchKey.toLowerCase() == queryLower) score += 60;
    
    // Partial matches get lower scores
    if (interaction.drugName.toLowerCase().contains(queryLower)) score += 50;
    if (interaction.foodToAvoid.toLowerCase().contains(queryLower)) score += 40;
    if (interaction.description.toLowerCase().contains(queryLower)) score += 30;
    if (interaction.searchKey.toLowerCase().contains(queryLower)) score += 25;
    if (interaction.foodToTake.toLowerCase().contains(queryLower)) score += 20;
    if (interaction.interactingWith.toLowerCase().contains(queryLower)) score += 15;
    if (interaction.timeToTake.toLowerCase().contains(queryLower)) score += 10;
    
    return score;
  }

  Widget _buildHighlightedText(String text, String query) {
    if (query.isEmpty) {
      return Text(text);
    }
    
    final queryLower = query.toLowerCase();
    final textLower = text.toLowerCase();
    final index = textLower.indexOf(queryLower);
    
    if (index == -1) {
      return Text(text);
    }
    
    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
          height: 1.3,
        ),
        children: [
          TextSpan(text: text.substring(0, index)),
          TextSpan(
            text: text.substring(index, index + query.length),
            style: TextStyle(
              backgroundColor: Colors.yellow.shade200,
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(text: text.substring(index + query.length)),
        ],
      ),
    );
  }

  void _loadInteractions() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });
    try {
      final interactions = await MedicineService().getFoodDrugInteractions();
      if (!mounted) return;
      setState(() {
        _allInteractions = interactions;
        _filteredInteractions = List.from(interactions);
        // Sort alphabetically by drug name when initially loaded
        _filteredInteractions.sort((a, b) {
          final nameA = (a.drugName ?? '').trim().toLowerCase();
          final nameB = (b.drugName ?? '').trim().toLowerCase();
          return nameA.compareTo(nameB);
        });
        _isLoading = false;
      });
      if (_allInteractions.isNotEmpty && mounted) {
        _animationController.forward(from: 0);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _allInteractions = [];
        _filteredInteractions = [];
        _isLoading = false;
      });
    }
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _filteredInteractions = List.from(_allInteractions);
      // Sort alphabetically by drug name when search is cleared
      _filteredInteractions.sort((a, b) {
        final nameA = (a.drugName ?? '').trim().toLowerCase();
        final nameB = (b.drugName ?? '').trim().toLowerCase();
        return nameA.compareTo(nameB);
      });
    });
  }

  Widget _buildSearchBar() {
    return Container(
      margin: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search drugs, foods, or interactions...',
          hintStyle: TextStyle(
            color: Colors.grey.shade500,
            fontSize: 16,
          ),
          prefixIcon: Icon(
            Icons.search,
            color: Colors.grey.shade600,
            size: 24,
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    color: Colors.grey.shade600,
                    size: 20,
                  ),
                  onPressed: _clearSearch,
                )
              : null,
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        style: TextStyle(
          fontSize: 16,
          color: Colors.black87,
        ),
        onChanged: (value) {
          setState(() {
            _isSearching = value.isNotEmpty;
          });
        },
      ),
    );
  }

  Widget _buildSearchResultsHeader() {
    if (_searchQuery.isEmpty) return SizedBox.shrink();
    
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.search,
            size: 16,
            color: Colors.grey.shade600,
          ),
          SizedBox(width: 8),
          Text(
            '${_filteredInteractions.length} result${_filteredInteractions.length == 1 ? '' : 's'} for "$_searchQuery"',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          Spacer(),
          if (_filteredInteractions.length != _allInteractions.length)
            TextButton(
              onPressed: _clearSearch,
              child: Text(
                'Clear',
                style: TextStyle(
                  color: Colors.purple.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImage() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.purple.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.medication_outlined,
        color: Colors.purple.shade400,
        size: 28,
      ),
    );
  }

  Widget _buildShimmerCard() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Medicine icon placeholder
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drug name placeholder
                  Container(
                    width: double.infinity,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  SizedBox(height: 8),
                  // Description placeholders (two lines)
                  Container(
                    width: double.infinity,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  SizedBox(height: 4),
                  Container(
                    width: 200,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  SizedBox(height: 10),
                  Row(
                    children: [
                      // Food to avoid placeholder
                      Container(
                        width: 120,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      SizedBox(width: 12),
                      // Time to take placeholder
                      Container(
                        width: 80,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Chevron icon placeholder
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmerLoading() {
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: 8,
      itemBuilder: (context, index) {
        return Shimmer.fromColors(
          baseColor: Colors.grey.shade300,
          highlightColor: Colors.grey.shade100,
          child: _buildShimmerCard(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.purple.shade600,
        elevation: 0,
        title: Text(
          'Drug-Food Interactions',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          _buildSearchResultsHeader(),
          Expanded(
            child: _isLoading
                ? _buildShimmerLoading()
                : _filteredInteractions.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: _filteredInteractions.length,
                        itemBuilder: (context, index) {
                          final interaction = _filteredInteractions[index];
                          return _buildInteractionCard(interaction, index);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final isSearchEmpty = _searchQuery.isNotEmpty && _filteredInteractions.isEmpty;
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isSearchEmpty ? Icons.search_off : Icons.medication_liquid,
            size: 72,
            color: Colors.grey.shade300,
          ),
          SizedBox(height: 24),
          Text(
            isSearchEmpty ? 'No results found' : 'No interactions found',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          SizedBox(height: 12),
          Container(
            width: 300,
            child: Text(
              isSearchEmpty
                  ? 'Try different keywords or check your spelling'
                  : 'Try adjusting your search to find what you\'re looking for',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 16,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          if (isSearchEmpty) ...[
            SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _clearSearch,
              icon: Icon(Icons.clear),
              label: Text('Clear Search'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple.shade600,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInteractionCard(FoodDrugInteraction interaction, int index) {
    final begin = (index % 10) * 0.1;
    final end = (begin + 0.1).clamp(0.0, 1.0);
    final interval = Interval(begin, end, curve: Curves.easeOut);

    return SlideTransition(
      position: Tween<Offset>(
        begin: Offset(0, 0.05),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _animationController,
        curve: interval,
      )),
      child: FadeTransition(
        opacity: CurvedAnimation(
          parent: _animationController,
          curve: interval,
        ),
        child: Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: EdgeInsets.only(bottom: 12),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => MedicineDetailScreen(interaction: interaction),
                ),
              );
            },
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildImage(),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHighlightedText(interaction.drugName, _searchQuery),
                        SizedBox(height: 8),
                        Text(
                          interaction.description,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(Icons.fastfood, size: 14, color: Colors.amber.shade700),
                            SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                'Avoid: ${interaction.foodToAvoid}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.amber.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            SizedBox(width: 12),
                            Icon(Icons.schedule, size: 14, color: Colors.blue.shade700),
                            SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                interaction.timeToTake,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: Colors.grey.shade400,
                    size: 24,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
