
#use Lingua::EN::Keywords::Yahoo qw(keywords);
#use LWP::Debug qw(+);
use Lingua::EN::Keywords;
use WWW::Mechanize;
use WWW::Wikipedia;
use AI::Categorizer::FeatureVector;
use HTML::TagFilter;

# define constants
my $livejournal_search = 'http://www.livejournal.com/site/search.bml';

# input parameters
my $interest = $ARGV[0];
my $output_filename = $ARGV[1];
my $limit_blog = $ARGV[2];

# object initialization
my $mech = WWW::Mechanize->new();
my $tf = new HTML::TagFilter;

# logic starts
$mech->get($livejournal_search);

$mech->submit_form(
        form_number => 1,
        fields      => {
            int    => $interest
        }
       );

my $search_result = $mech->content();
my $stripped_result;

$search_result =~ m/Results for communities interested in.*?<\/h1>(.*)/s;
$stripped_result = $1;
$stripped_result =~ m/(.*?)<h1>Results for users interested in.*?<\/h1>(.*)/s;

my $stripped_result_for_community = $1;
my $stripped_result_for_people = $2;

# obtain list of blogs interesting of topic
# interesting communities
my @blogs;

while ($stripped_result_for_community =~ s/<img.*?><a href=\'(.*?)\'><b>(.*?)<\/b><\/a>(.*)/$3/s) {
  my %blog;
  $blog{'url'} = $1;
  $blog{'user'} = $2;
  push @blogs, \%blog;
}

# interesting people
while ($stripped_result_for_people =~ s/<span class=(\'|\")ljuser(\'|\").*?>.*?<\/a><a href=(\'|\")(.*?)(\'|\")><b>(.*?)<\/b><\/a>(.*)/$7/s) {
  my %blog;
  $blog{'url'} = $4;
  $blog{'user'} = $6;
  push @blogs, \%blog;
}

# traverse blogs of topic
my %reply_ratio;
my %commenter_reply_times;
my $limit = $limit_blog ne '' ? $limit_blog : 20;
my $count = 0;
my $intervals = 2;
my $multiply = 1e16;

foreach (@blogs) {  
  my $blog = $_;
  my $url = $blog->{'url'};
  my $blog_author = $blog->{'user'};
  my $html_content;

  $count++;
  last if $count >= $limit;
#$url = 'http://community.livejournal.com/ask_me_anything/';
  $mech->get($url);
  $html_content = $mech->content();  
  #print $html_content . "\n";
  
  print $url . "\n";

  # traverse posts in blog 
  while (1) {

    my $blog_with_comment = 0;
    $blog_with_comment = 1 if ($html_content =~ s/<ul class="entrycmdlinks"><li><a href="(.*?)">(.*?)<\/a><\/li>(.*?)<\/ul>(.*)/$4/s);

    $blog_with_comment = 2 if ($blog_with_comment == 0 && $html_content =~ s/<a href=[\'\"](.*?)\?mode=reply[\'\"]>.*?comment.*?<\/a>(.*)/$2/s);

    print "blog comment type: $blog_with_comment.\n";
    last if $blog_with_comment == 0;

    my $comment_url = $1;
    my $comment_html;

    $comment_url =~ s/.*<a href=[\'\"](.*?[^>])$/$1/s if $blog_with_comment == 2;

    print "comment url: $comment_url\n";
    sleep $intervals;
    #exit if $blog_with_comment == 2;

    $mech->get($comment_url);
    $comment_html = $mech->content(); 

    my %comment_id_mapping;
    my %comment_keywords_mapping;

    if ($comment_html =~ m/$interest/s) {
      print "Find $interest in post and comments.\n";
    }
    else {
      next;
    }

    
 
    while (1) {
      my $comment_content = '';
      my $comment_id = '';

      if ($comment_html =~ s/<a name=(\'|\")(t\d*?)(\'|\")><\/a>.*?<table.*?class=\'talk-comment\'>(.*?)<\/table>(.*)/$5/s) {
        $comment_content = $4;
        $comment_id = $2;
      }
      elsif ($comment_html =~ s/<a name=(\'|\")(t\d*?)(\'|\")><\/a>.*?<div.*?>(.*?)<div class=(\"|\')quickreply(\"|\').*?><\/div>(.*)/$7/s) {
        $comment_content = $4;
        $comment_id = $2;
      }
      elsif ($comment_html =~ s/<ul class=(\"|\')comments(\"|\')>.*?<div class=(\"|\')entry(\"|\') id=(\"|\')ljcm(t\d.*?)(\"|\')>(.*?)<ul class=(\"|\')comments(\"|\')>/$8/s) {
        $comment_content = $8;
        $comment_id = $6;
      }
      else {
        last;
      }
    
      print "comment id: $2\n";

#print $1 . ":" . $2 . ":" . $3 . ":" . $4 . ":" . $5 . "\n";
#print $4 . "\n";
 
      my $commentor_blog_url;
      my $commentor;

      if ($comment_content =~ s/<span class=(\'|\")ljuser(\'|\").*?>.*?<\/a><a href=(\'|\")(.*?)(\'|\")><b>(.*?)<\/b><\/a>(.*)/$7/s) {
        print "Parsing comments.\n";
        $commentor_blog_url = $4;
        $commentor = $6;
      }
      elsif ($comment_content =~ s/<img.*?alt=(\"|\')\[User Picture\](\"|\').*?\/>.*?<b>(.*?)<\/b>(.*)/$4/s) {
        print "Parsing comments.\n";
        $commentor_blog_url = '';
        $commentor = $3;
      }
      elsif ($comment_content =~ s/<i>\(Anonymous\)<\/i>(.*)/$1/s) {
        print "Parsing comments.\n";
        $commentor_blog_url = '';
        $commentor = 'Anonymous';
      }
      else {
        print $comment_content . "\n";
        #exit;
        next;
      }

      print "Commentor: $commentor\n";
      print "Commentor Blog URL: $commentor_blog_url\n";
      #print $comment_content . "\n";

      next if ($commentor eq '' || $commentor =~ m/Anonymous/s);

      $comment_id_mapping{$comment_id} = $commentor;

      # obtain keywords
      #if ($comment_content =~ m/(l|L)ink<\/a>\).*?<td>(.*?)\(<a.*?>Reply to this<\/a>\)/s) {

      my $comment_text_with_html = '';
      my $parsed_comment = 0;

      if ($comment_content =~ m/(l|L)ink<\/a>\)(.*?)\(<a.*?>Reply to this<\/a>\)/s) {
        $comment_text_with_html = $2;
        $parsed_comment = 1;
      }
      elsif ($comment_content =~ m/<div class=(\"|\')entrycontent(\"|\')>(.*?)<div class=(\"|\')entryfooter(\"|\')>/s) {
        $comment_text_with_html = $3;
        $parsed_comment = 1;
      }

      if ($parsed_comment == 1) {
        my $comment_text = $tf->filter($comment_text_with_html);
        print "comment text: " . $2 . "\n";
        my @comment_keywords = keywords($comment_text);
        my @stripped_keywords;
        foreach (@comment_keywords) {
          print "keyword: " . $_ . "\n";
          shift @comment_keywords;
          push @stripped_keywords, $_;
        }
        $comment_keywords_mapping{$comment_id} = \@stripped_keywords;    
      }

      print $comment_content . "\n";

      # if this is a reply comment      
      my $reply_comment = 0;
      my $comment_reply_parent = '';

      if ($comment_content =~ m/Reply to this<\/a>\).*?\(<a href=(\'|\")(.*?)\#(.*?)(\'|\")>(Parent|Thread)<\/a>/s) {
        $reply_comment = 1;
        $comment_reply_parent = $3;
      }
      elsif ($comment_content =~ m/<ul class=(\"|\')entrycmdlinks(\"|\')>.*?<a href=(\"|\')(.*?)\#(.*?)(\'|\")>.*?<\/a>/s) {
        $reply_comment = 1;
        $comment_reply_parent = $5;
      }

      if ($reply_comment == 1) {
        print "A reply comment.\n";
        my $comment_reply_parent_commentor = $comment_id_mapping{$comment_reply_parent};

        #if (defined $reply_times{$commentor}{$comment_reply_parent_commentor}) {
        #  $reply_times{$commentor}{$comment_reply_parent_commentor}++;
        #}
        #else {
        #  $reply_times{$commentor}{$comment_reply_parent_commentor} = 1;
        #}
        #print $commentor . " reply to " . $comment_reply_parent_commentor . " " . $reply_times{$commentor}{$comment_reply_parent_commentor} . " times " . "\n";

        #my @this_comment_keywords = $comment_keywords_mapping{$comment_id};
        #my @reply_comment_keywords = $comment_keywords_mapping{$comment_reply_parent};


        # transform comment text to feature and calculate cosine value
        my %keywords;
        print $comment_id . " to " . $comment_reply_parent . "\n";
        print "echo keywords of comment.\n";
        foreach $keyword (@{$comment_keywords_mapping{$comment_id}}) {
          print "$keyword.\n";
          $keywords{$comment_id}{$keyword} = 1;
        }
        print "echo keywords of comment parent.\n";
        foreach $keyword (@{$comment_keywords_mapping{$comment_reply_parent}}) {
          print "$keyword.\n";
          $keywords{$comment_reply_parent}{$keyword} = 1;
        }

        my $this_comment_features = new AI::Categorizer::FeatureVector (features => $keywords{$comment_id});
        my $reply_comment_features = new AI::Categorizer::FeatureVector (features => $keywords{$comment_reply_parent});
        
        print "this comment features: " . $this_comment_features->length . "\n";
        print "reply comment features: " . $reply_comment_features->length . "\n";

        my $vector_dot = $this_comment_features->dot($reply_comment_features);
        my $vector_norm = $this_comment_features->normalize() * $reply_comment_features->normalize();
        my $cosine = $vector_dot / $vector_norm;

        print "Dot: $vector_dot, Norm: $vector_norm, Cosine of feasure: $cosine\n";

        $cosine *= $multiply;

        print "$commentor -> $comment_reply_parent_commentor: $cosine\n";
        $reply_ratio{$commentor}{$comment_reply_parent_commentor} += $cosine if $cosine != 0;

        # record reply times from commenter to comment parent
        if (defined $commenter_reply_times{$commentor}{$comment_reply_parent_commentor}) {
          $commenter_reply_times{$commentor}{$comment_reply_parent_commentor}++;
        }
        else {
          $commenter_reply_times{$commentor}{$comment_reply_parent_commentor} = 1;
        }
      }
    }
  }
}

# refine link weight
print "calculating link weight in network.\n";
foreach $commenter (keys %commenter_reply_times) {
  next if $commenter eq '';
  my $reply_times_for_commenter = 0;
  foreach $reply_parent_commenter (keys %{$commenter_reply_times{$commenter}}) {
    $reply_times_for_commenter += $commenter_reply_times{$commenter}{$reply_parent_commenter};
  }
  print "$commenter totally replys " . $reply_times_for_commenter . " times.\n";
  foreach $reply_parent_commenter (keys %{$commenter_reply_times{$commenter}}) {
    next if $reply_parent_commenter eq '';
    print "$commenter replys to $reply_parent_commenter " . $commenter_reply_times{$commenter}{$reply_parent_commenter} . " times.\n";
    $reply_ratio{$commenter}{$reply_parent_commenter} += $commenter_reply_times{$commenter}{$reply_parent_commenter} / $reply_times_for_commenter;
  }
}

# echo traversing result and output file

print "echo reply network: \n";

open(OUTPUTFILE, ">>$output_filename");

foreach $commentor (keys %reply_ratio) {
  foreach $reply_parent_commentor (keys %{$reply_ratio{$commentor}}) {
    print "$commentor -> $reply_parent_commentor: " . $reply_ratio{$commentor}{$reply_parent_commentor} . "\n";
    print OUTPUTFILE "$commentor\t$reply_parent_commentor\t" . $reply_ratio{$commentor}{$reply_parent_commentor} . "\n"; 
  }
}

close(OUTPUTFILE);

exit;

