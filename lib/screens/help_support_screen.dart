import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class HelpSupportScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Help & Support',
          style: TextStyle(
            color: Colors.black, 
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        leading: Container(
          margin: EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF6B46C1), Color(0xFF5E4B8B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Color(0xFF6B46C1).withOpacity(0.3),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Icon(Icons.help_outline, color: Colors.white, size: 24),
        ),
        actions: [
          Container(
            margin: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: Icon(Icons.info_outline, color: Color(0xFF5E4B8B)),
              onPressed: () {
                _showAppInfo(context);
              },
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            // Header Section
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF6B46C1), Color(0xFF5E4B8B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Color(0xFF6B46C1).withOpacity(0.3),
                    blurRadius: 15,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.support_agent,
                    color: Colors.white,
                    size: 48,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'How can we help you?',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Get in touch with our support team',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            
            SizedBox(height: 24),
            
            // Contact Buttons Section
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 20,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Color(0xFF5E4B8B).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.contact_support,
                          color: Color(0xFF5E4B8B),
                          size: 20,
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Contact Options',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 20),
                  
                  // Email Button
                  _buildContactButton(
                    context: context,
                    icon: Icons.email_outlined,
                    title: 'Email Support',
                    subtitle: 'jagadeem1@srmist.edu.in',
                    onTap: () => _launchEmail(),
                    color: Color(0xFF5E4B8B),
                  ),
                  
                  SizedBox(height: 16),
                  
                  // Call Button
                  _buildContactButton(
                    context: context,
                    icon: Icons.phone_outlined,
                    title: 'Call Support',
                    subtitle: '+91 7449277556',
                    onTap: () => _launchPhone(),
                    color: Color(0xFF5E4B8B),
                  ),
                  
                  SizedBox(height: 16),
                  
                  // Feedback Button
                  _buildContactButton(
                    context: context,
                    icon: Icons.feedback_outlined,
                    title: 'Send Feedback',
                    subtitle: 'Help us improve your experience',
                    onTap: () => _launchFeedback(context),
                    color: Color(0xFF5E4B8B),
                  ),
                ],
              ),
            ),
            
            SizedBox(height: 32),
            
            // FAQ Section
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 20,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Color(0xFF5E4B8B).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.question_answer_outlined,
                          color: Color(0xFF5E4B8B),
                          size: 20,
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Frequently Asked Questions',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 20),
                  
                  _buildFAQItem(
                    'How do I set up medication reminders?',
                    'Go to the home screen and tap the "+" button to add a new medication. Set the time and frequency for your reminders.',
                    Icons.add_alarm,
                  ),
                  
                  Divider(height: 1, color: Colors.grey.shade200),
                  
                  _buildFAQItem(
                    'Can I customize notification sounds?',
                    'Yes! Go to Settings > Notifications and toggle off "Use Default Alarm Sound" to select your own audio file.',
                    Icons.music_note,
                  ),
                  
                  Divider(height: 1, color: Colors.grey.shade200),
                  
                  _buildFAQItem(
                    'How do I share my medication schedule?',
                    'Use the Caretaker feature in the app to generate a share code and send it to your family member or caregiver.',
                    Icons.share,
                  ),
                  
                  Divider(height: 1, color: Colors.grey.shade200),
                  
                  _buildFAQItem(
                    'What if I miss a medication dose?',
                    'The app will show missed doses in your medication history. You can mark them as taken or skipped.',
                    Icons.history,
                  ),
                ],
              ),
            ),
            
            SizedBox(height: 32),
            
            // Association Section
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 20,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Text(
                    'In Association with',
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 14,
                      color: Color(0xFF8E8E8E),
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  
                  SizedBox(height: 20),
                  
                  // Logos Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Left Logo (slogo.png)
                      Container(
                        width: 90,
                        height: 90,
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Image.asset(
                          'assets/images/slogo.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                      
                      SizedBox(width: 40),
                      
                      // Right Logo (slogop.png)
                      Container(
                        width: 90,
                        height: 90,
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Image.asset(
                          'assets/images/slogop.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
  
  Widget _buildContactButton({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required Color color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: color,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildFAQItem(String question, String answer, IconData icon) {
    return ExpansionTile(
      leading: Container(
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Color(0xFF5E4B8B).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Color(0xFF5E4B8B), size: 16),
      ),
      title: Text(
        question,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: Colors.black87,
        ),
      ),
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Text(
            answer,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
  
  void _showAppInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          contentPadding: EdgeInsets.fromLTRB(24, 20, 24, 16),
          insetPadding: EdgeInsets.symmetric(horizontal: 20),
          title: Row(
            children: [
              Icon(Icons.info, color: Color(0xFF5E4B8B)),
              SizedBox(width: 8),
              Text('App Information', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: Container(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(thickness: 1.5),
                  SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Color(0xFF5E4B8B).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        'Development Team',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Color(0xFF5E4B8B),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 20),
                  
                  // Shantanu Card
                  _buildSimpleDeveloperCard(
                    dialogContext: dialogContext,
                    name: 'Shantanu',
                    email: 'shantanues234@gmail.com',
                    linkedin: 'linkedin.com/in/shantanu-v-928152277'
                  ),
                  
                  SizedBox(height: 16),
                  
                  // Giridharan Card
                  _buildSimpleDeveloperCard(
                    dialogContext: dialogContext,
                    name: 'Giridharan R',
                    email: 'giriraju005@gmail.com',
                    linkedin: 'linkedin.com/in/giridharan-r-971137256'
                  ),
                  
                  SizedBox(height: 16),
                  
                  // Divyan Card
                  _buildSimpleDeveloperCard(
                    dialogContext: dialogContext,
                    name: 'H.Divyan',
                    email: 'h.divyan7@gmail.com',
                    linkedin: 'linkedin.com/in/h-divyan'
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('Close'),
            ),
          ],
        );
      },
    );
  }
  
  Widget _buildSimpleDeveloperCard({
    required BuildContext dialogContext,
    required String name,
    required String email,
    required String linkedin,
  }) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF6B46C1), Color(0xFF5E4B8B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.person, size: 24, color: Colors.white),
              ),
              SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  Text(
                    'Developer',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: 16),
          Divider(),
          SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Email button
              InkWell(
                onTap: () async {
                  try {
                    final emailUri = Uri(
                      scheme: 'mailto',
                      path: email,
                      queryParameters: {
                        'subject': 'MedicFood App Support'
                      }
                    );
                    
                    await launchUrl(emailUri);
                  } catch (e) {
                    print('Error launching email: $e');
                  }
                },
                child: Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.shade100.withOpacity(0.3),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.email,
                    size: 20,
                    color: Colors.red.shade700,
                  ),
                ),
              ),
              
              SizedBox(width: 24),
              
              // LinkedIn button
              InkWell(
                onTap: () async {
                  try {
                    // Ensure the URL has https:// prefix
                    String url = linkedin;
                    if (!url.startsWith('http://') && !url.startsWith('https://')) {
                      url = 'https://$url';
                    }
                    
                    // Try to launch in external application first
                    await launchUrl(
                      Uri.parse(url),
                      mode: LaunchMode.externalApplication,
                    );
                  } catch (e) {
                    print('Error launching LinkedIn: $e');
                    
                    // Fallback to platform default browser if external app fails
                    try {
                      String url = linkedin;
                      if (!url.startsWith('http://') && !url.startsWith('https://')) {
                        url = 'https://$url';
                      }
                      
                      await launchUrl(
                        Uri.parse(url),
                        mode: LaunchMode.platformDefault,
                      );
                    } catch (e) {
                      print('Error launching LinkedIn in browser: $e');
                    }
                  }
                },
                child: Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Color(0xFF0077B5).withOpacity(0.1),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0xFF0077B5).withOpacity(0.2),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: FaIcon(
                    FontAwesomeIcons.linkedin,
                    size: 20,
                    color: Color(0xFF0077B5),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  // This method was removed as we now launch URLs directly
  
  // This section has been replaced by _buildSimpleDeveloperCard
  
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade700,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: Color(0xFF5E4B8B),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
  
  Future<void> _launchEmail() async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'jagadeem1@srmist.edu.in',
      query: 'subject=Medic App Support Request',
    );
    
    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
    } else {
      // Fallback: copy email to clipboard
      // You can add clipboard functionality here if needed
    }
  }
  
  Future<void> _launchPhone() async {
    final Uri phoneUri = Uri(
      scheme: 'tel',
      path: '+917449277556',
    );
    
    if (await canLaunchUrl(phoneUri)) {
      await launchUrl(phoneUri);
    }
  }
  
  Future<void> _launchFeedback(BuildContext context) async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(Icons.feedback, color: Color(0xFF5E4B8B)),
              SizedBox(width: 8),
              Text('Feedback', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'We\'d love to hear from you! How can we help improve your experience?',
                style: TextStyle(fontSize: 14),
              ),
              SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _launchEmail();
                      },
                      icon: Icon(Icons.email, size: 16),
                      label: Text('Email'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFF5E4B8B),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _launchPhone();
                      },
                      icon: Icon(Icons.phone, size: 16),
                      label: Text('Call'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFF5E4B8B),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
          ],
        );
      },
    );
  }
  
  // This method was removed as we now use SnackBars for error messages
} 