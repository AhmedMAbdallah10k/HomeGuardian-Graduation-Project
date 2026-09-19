import 'package:flutter/material.dart';

class _AlertsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 90,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent Alerts',
            style: TextStyle(color: Colors.red[400], fontSize: 14),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.warning, color: Colors.redAccent, size: 18),
              SizedBox(width: 4),
              Text(
                'Front Door Opened',
                style: TextStyle(color: Colors.black, fontSize: 13),
              ),
              SizedBox(width: 12),
              Icon(Icons.check_circle, color: Colors.green, size: 18),
              SizedBox(width: 4),
              Text(
                'All Windows Closed',
                style: TextStyle(color: Colors.black54, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: 0.7,
            backgroundColor: Colors.red[100],
            valueColor: AlwaysStoppedAnimation<Color>(Colors.redAccent),
          ),
        ],
      ),
    );
  }
}

class _DeviceStatusCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 140,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.devices, color: Colors.blueGrey, size: 40),
          const SizedBox(height: 8),
          Text(
            'Device Status',
            style: TextStyle(
              color: Colors.blueGrey,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'All sensors online',
            style: TextStyle(color: Colors.green, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _RecentActivityCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent Activity',
          style: TextStyle(color: Colors.grey[700], fontSize: 14),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Center(
            child: Text(
              'No unusual activity detected',
              style: TextStyle(color: Colors.grey[400]),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmergencyContactsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Emergency Contacts',
            style: TextStyle(color: Colors.red[400], fontSize: 14),
          ),
          const SizedBox(height: 8),
          Expanded(child: _ContactItem('Police', '100')),
          Expanded(child: _ContactItem('Fire Department', '101')),
          Expanded(child: _ContactItem('Family Doctor', '102')),
        ],
      ),
    );
  }
}

class _ContactItem extends StatelessWidget {
  final String name;
  final String number;
  const _ContactItem(this.name, this.number);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.phone, color: Colors.redAccent, size: 18),
          const SizedBox(width: 8),
          Text(name, style: TextStyle(color: Colors.black)),
          const SizedBox(width: 8),
          Text(number, style: TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }
}

class _NetworkStatusCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Network Status',
            style: TextStyle(color: Colors.blue[400], fontSize: 14),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.wifi, color: Colors.blue, size: 18),
              const SizedBox(width: 8),
              Text('Connected', style: TextStyle(color: Colors.green)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Last checked: 2 min ago',
            style: TextStyle(color: Colors.grey[400], fontSize: 12),
          ),
        ],
      ),
    );
  }
}
