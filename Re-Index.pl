#!C:/strawberry/perl/bin/perl.exe
###################################################################################
# Re-Index.pl by Jason Hensler
# Starts re-index job for jira. Tested with JIra 5.2.4 and 6.0.7
###################################################################################
 
#disable ssl verfication, using this for self-signed cert otherwise comment out.
$ENV{'PERL_LWP_SSL_VERIFY_HOSTNAME'} = 0;
use warnings;
use diagnostics;
use Data::Dumper;
use LWP::UserAgent;
 
# Change these
my $user = "admin_user";
my $pass = "";
my $jira_url = "https://jira/jira/";
my $cookie_jar = $ENV{'HOME'}; #change this if you need to, should only be need is there is a permissions issue.
my $index_type = 1; #This is for jira 5.2 and above. Set to 1 for background re-index or 0 for locking index.
my $error = 0;
 
 
#setup initial connection paramaters
my $status;
print("Creating connection to [$jira_url]... \n");
my $ua = LWP::UserAgent->new;
$ua->cookie_jar({ file => "$cookie_jar/\.cookies.txt" });
$ua->default_header('X-Atlassian-Token' => 'no-check');
 
 
#do login
$status = $ua->post($jira_url.'secure/admin/IndexAdmin.jspa', [ 'os_username'   => $user, 'os_password'  => $pass]);
if($status->header('X-Seraph-LoginReason') eq "AUTHENTICATED_FAILED" || $status->code !=200) {
print("Could not login to jira, verify username and password!\n");
$error = 1;
} else {
    print("Successfully logged in to Jira.\n");
    #do websudo
    $status = $ua->post($jira_url.'secure/admin/WebSudoAuthenticate.jspa',[ 'webSudoPassword'   => $pass]);
 
    # I'm using the http code here because the user header check stays ok and I didn't want to grep the output for an error...
    # If we pass sudo check we get redirected to /secure/ and code is 302, otherwise we get served an error page with status 200
    if($status->code != 302) {
        unlink('$cookie_jar/.cookies.txt');
        print("We did not sudo properly, check that your password is good and the your user is an admin!\n");
        $error = 1;
    } else {
        print("Successfully passed websudo, kicking off indexing... ");
        #do re-index
        if($index_type == 1) {$index_type='background';}
        $status = $ua->post($jira_url.'IndexReIndex.jspa', [ 'indexPathOption' => 'DEFAULT','Re-Index' =>'Re-Index', 'indexingStrategy' => $index_type]);
        if($status->code != 302) {
            print("Could not start re-index, check that your password is good and the your user is an admin!\n");
            $error = 1;
        } else {
            print("Re-index has started.\n");
            print ("Task url: ".$status->header('location')."\n");
            my $finished = 0;
            my $temp_file = "out.html";
            while ($finished eq 0) {
                my $progress = $ua->mirror($status->header('location'),$temp_file);
                sleep(5);
                open(my $tmp, "<", $temp_file);
                while(eof($tmp) != 1) {
                    my $line = readline($tmp);
                    $line =~ s/^\s+|\s+$//g;
                    #print($line);
                    if ( substr($line,0,15) eq "Re-indexing is ") {
                        print ("Reindex is at ".substr($line,15,3)."\n");
                        if(substr($line,15,3) eq "100") {
                            $finished = 1;
                            print ("DONE!\n");
                        }
                    }
                }
                unlink($temp_file);
                sleep(5);
            }
             
            $error = 0;
        }
    }
}
unlink('$cookie_jar/.cookies.txt');
exit $error;
