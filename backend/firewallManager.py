import subprocess
import os

class FirewallManager:
    def __init__(self, internet_iface, local_iface, port):
        self.scripts_dir = os.path.join(os.path.dirname(__file__), 'firewall')
        self.internet_iface = internet_iface
        self.local_iface = local_iface
        self.portal_port = port
    
    def run_script(self, script_name, parameters=None):
        script_path = os.path.join(self.scripts_dir, script_name)
        
        try:
            if parameters:
                command = [script_path] + parameters
                result = subprocess.run(
                    command, 
                    check=True, 
                    capture_output=True, 
                    text=True
                )
            else:
                result = subprocess.run(
                    [script_path], 
                    check=True, 
                    capture_output=True, 
                    text=True
                )
            
            print(f"✅ {result.stdout.strip()}")
            return True
            
        except subprocess.CalledProcessError as e:
            print(f"❌ Error ejecutando {script_name}: {e.stderr}")
            return False
    
    def setup_captive_portal(self):
        return self.run_script('block_all.sh', [self.internet_iface, self.local_iface, self.portal_port])
    
    def unlock_user(self, user_ip):
        return self.run_script('unlock_user.sh', [user_ip])
    