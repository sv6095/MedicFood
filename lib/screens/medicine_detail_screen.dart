import 'package:flutter/material.dart';
import '../models/medicine.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shimmer/shimmer.dart';

class MedicineDetailScreen extends StatefulWidget {
  final FoodDrugInteraction interaction;

  const MedicineDetailScreen({Key? key, required this.interaction}) : super(key: key);

  @override
  _MedicineDetailScreenState createState() => _MedicineDetailScreenState();
}

class _MedicineDetailScreenState extends State<MedicineDetailScreen> with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 500),
    );
    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeIn);
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Widget _buildImage(String url) {
    if (url == 'na' || url.isEmpty) {
      return Container(
        width: 60,
        height: 60,
        color: Colors.grey.shade200,
        child: Icon(Icons.image_not_supported, color: Colors.grey, size: 32),
      );
    } else {
      return Image.network(
        url,
        width: 60,
        height: 60,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: 60,
            height: 60,
            color: Colors.grey.shade200,
            child: Icon(Icons.broken_image, color: Colors.grey, size: 32),
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: null,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.purple.shade600.withOpacity(0.95),
        elevation: 0,
        title: Text(
          widget.interaction.drugName,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 22,
            letterSpacing: 0.5,
          ),
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.purple.shade50, Colors.white, Colors.purple.shade50],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(0, 90, 0, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 500),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: 32), // Extra space at the top
                    // Time to Take Section
                    _ModernInfoCard(
                      title: 'Time to Take',
                      content: widget.interaction.timeToTake,
                      accentColor: Colors.purple.shade200,
                    ),
                    SizedBox(height: 24),
                    // Interacting With Section
                    _ModernInfoCard(
                      title: 'Interacting With',
                      content: widget.interaction.interactingWith,
                      accentColor: Colors.blue.shade400,
                    ),
                    if (widget.interaction.url3 != 'na' && widget.interaction.url3.isNotEmpty && widget.interaction.url3.trim().isNotEmpty && (widget.interaction.url3.startsWith('http://') || widget.interaction.url3.startsWith('https://'))) ...[
                      SizedBox(height: 16),
                      _ModernImageCard(
                        label: 'Interacting With Image',
                        url: widget.interaction.url3,
                      ),
                      SizedBox(height: 24),
                    ] else ...[
                      SizedBox(height: 24),
                    ],
                    // Description Section
                    _ModernInfoCard(
                      title: 'Description',
                      content: widget.interaction.description,
                      accentColor: Colors.purple.shade400,
                    ),
                    SizedBox(height: 24),
                    // Food to Avoid Section
                    _ModernInfoCard(
                      title: 'Food to Avoid',
                      content: widget.interaction.foodToAvoid,
                      accentColor: Colors.red.shade400,
                    ),
                    if (widget.interaction.url2 != 'na' && widget.interaction.url2.isNotEmpty && widget.interaction.url2.trim().isNotEmpty && (widget.interaction.url2.startsWith('http://') || widget.interaction.url2.startsWith('https://'))) ...[
                      SizedBox(height: 16),
                      _ModernImageCard(
                        label: 'Food to Avoid Image',
                        url: widget.interaction.url2,
                      ),
                      SizedBox(height: 24),
                    ] else ...[
                      SizedBox(height: 24),
                    ],
                    // Food to Take Section
                    _ModernInfoCard(
                      title: 'Food to Take',
                      content: widget.interaction.foodToTake,
                      accentColor: Colors.green.shade400,
                    ),
                    if (widget.interaction.url1 != 'na' && widget.interaction.url1.isNotEmpty && widget.interaction.url1.trim().isNotEmpty && (widget.interaction.url1.startsWith('http://') || widget.interaction.url1.startsWith('https://'))) ...[
                      SizedBox(height: 16),
                      _ModernImageCard(
                        label: 'Food to Take Image',
                        url: widget.interaction.url1,
                      ),
                      SizedBox(height: 24),
                    ] else ...[
                      SizedBox(height: 24),
                    ],
                    SizedBox(height: 32), // Extra space at the bottom
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoSection(String title, String content) {
    return Card(
      elevation: 2,
      margin: EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.purple.shade600,
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(height: 8),
            Text(
              content.isNotEmpty ? content : 'N/A',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade800,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Modern info card with accent bar
class _ModernInfoCard extends StatelessWidget {
  final String title;
  final String content;
  final Color accentColor;
  const _ModernInfoCard({required this.title, required this.content, required this.accentColor});
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 5,
          height: 60,
          decoration: BoxDecoration(
            color: accentColor,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Card(
            elevation: 3,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            color: Colors.white.withOpacity(0.95),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: accentColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    content.isNotEmpty ? content : 'N/A',
                    style: TextStyle(
                      fontSize: 16.5,
                      color: Colors.grey.shade800,
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// Modern image card with fade/scale animation
class _ModernImageCard extends StatefulWidget {
  final String label;
  final String url;
  const _ModernImageCard({required this.label, required this.url});
  @override
  State<_ModernImageCard> createState() => _ModernImageCardState();
}

class _ModernImageCardState extends State<_ModernImageCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fade;
  late Animation<double> _scale;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: Duration(milliseconds: 600));
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _scale = Tween<double>(begin: 0.95, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _controller.forward();
  }
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showFullScreenImage(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) {
          return _FullScreenImageView(
            imageUrl: widget.url,
            label: widget.label,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        transitionDuration: Duration(milliseconds: 300),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Check if URL is valid before trying to load image
    final isValidUrl = widget.url != 'na' && 
                      widget.url.isNotEmpty && 
                      widget.url.trim().isNotEmpty &&
                      (widget.url.startsWith('http://') || widget.url.startsWith('https://'));
    
    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(
        scale: _scale,
        child: Column(
          children: [
            Text(
              widget.label,
              style: TextStyle(
                fontSize: 14.5,
                color: Colors.purple.shade300,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
            SizedBox(height: 8),
            Center(
              child: Card(
                elevation: 6,
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                color: Colors.white.withOpacity(0.85),
                child: Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.purple.shade100, width: 2),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.purple.shade100.withOpacity(0.18),
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: isValidUrl 
                        ? GestureDetector(
                            onTap: () => _showFullScreenImage(context),
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: Image.network(
                                widget.url,
                                width: 140,
                                height: 140,
                                fit: BoxFit.cover,
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) {
                                    return child;
                                  }
                                  return Shimmer.fromColors(
                                    baseColor: Colors.grey.shade300,
                                    highlightColor: Colors.grey.shade100,
                                    child: Container(
                                      width: 140,
                                      height: 140,
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade300,
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                  );
                                },
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    width: 140,
                                    height: 140,
                                    color: Colors.grey.shade200,
                                    child: Icon(Icons.broken_image, color: Colors.grey, size: 48),
                                  );
                                },
                              ),
                            ),
                          )
                        : Container(
                            width: 140,
                            height: 140,
                            color: Colors.grey.shade200,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.image_not_supported, color: Colors.grey, size: 48),
                                SizedBox(height: 8),
                                Text(
                                  'No Image',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Full-screen image viewer
class _FullScreenImageView extends StatefulWidget {
  final String imageUrl;
  final String label;

  const _FullScreenImageView({
    required this.imageUrl,
    required this.label,
  });

  @override
  State<_FullScreenImageView> createState() => _FullScreenImageViewState();
}

class _FullScreenImageViewState extends State<_FullScreenImageView> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_controller);
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.9),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return FadeTransition(
            opacity: _fadeAnimation,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Stack(
                children: [
                  // Close button
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 16,
                    right: 16,
                    child: GestureDetector(
                      onTap: () {
                        _controller.reverse().then((_) {
                          Navigator.of(context).pop();
                        });
                      },
                      child: Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                  // Image label
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 16,
                    left: 16,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        widget.label,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  // Main image
                  Center(
                    child: GestureDetector(
                      onTap: () {
                        _controller.reverse().then((_) {
                          Navigator.of(context).pop();
                        });
                      },
                      child: Container(
                        margin: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 20,
                              offset: Offset(0, 10),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.network(
                            widget.imageUrl,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                width: 300,
                                height: 300,
                                color: Colors.grey.shade800,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.broken_image,
                                      color: Colors.white,
                                      size: 64,
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      'Failed to load image',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}