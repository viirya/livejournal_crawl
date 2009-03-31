
# include modules 
use strict;
use Algorithm::Cluster qw/kcluster/;

# input parameters
my $network_filename = $ARGV[0];
my $cluster_num = $ARGV[1];
# order could be 'p' or 'n'
my $cluster_order = $ARGV[2];
my $output_filename = $ARGV[3];

# logic starts
open(NETWORKFILE, "<$network_filename"); 

my %network;
my %linkage;

my $i = 0;
while(<NETWORKFILE>) {
  chomp(my $line = $_);
  my @field = split /\t/, $line;

  if ($cluster_order == 'p') {
    $network{$field[0]}{$field[1]} = $field[2] if ($field[0] ne '' && $field[1] ne '' && $field[2] ne '');

    $linkage{$field[1]} = 1;
  }
  elsif ($cluster_order == 'n') {
    $network{$field[1]}{$field[0]} = $field[2] if ($field[0] ne '' && $field[1] ne '' && $field[2] ne '');

    $linkage{$field[0]} = 1;
  }
  
  ++$i;
}

close(NETWORKFILE);

# prepare cluster data
my (@orfname, @orfdata, @weight, @mask);
my ($field, $link);
my $linkage_num = scalar(keys %linkage);
$i = 0;

foreach $field (keys %network) {
  my @field_data;
  foreach $link (sort{ $a cmp $b } keys %linkage) {
    if (defined $network{$field}{$link}) {
      push @field_data, $network{$field}{$link};
    }
    else {
      push @field_data, 0;
    }
  }
  $orfname[$i] = $field;
  $orfdata[$i] = [@field_data];
  $mask[$i] = (1) *  $linkage_num;
  ++$i;
}

my %orfname_by_rowid;
$i=0;
$orfname_by_rowid{$i++} = $_, foreach(@orfname);

@weight = (1.0) x $linkage_num;

my %params = (
	nclusters =>         $cluster_num,
	transpose =>         0,
	npass     =>       100,
	method    =>       'a',
	dist      =>       'e',
	data      =>    \@orfdata,
	mask      =>       \@mask,
	weight    =>     \@weight,
);

my ($clusters, $error, $found) = kcluster(%params);

my %orfname_by_cluster;
$i=0;
foreach(@{$clusters}) {
  push @{$orfname_by_cluster{$_}}, $orfname_by_rowid{$i++};
}

for ($i = 0; $i < $params{"nclusters"}; $i++) {
  print "------------------\n";
  printf("Cluster %d:  %d ORFs\n\n",
          $i, scalar(@{$orfname_by_cluster{$i} })
  );

  print "\t$_\n", foreach( sort { $a cmp $b } @{$orfname_by_cluster{$i} } );
  print "\n";
}

exit;

# output cluster result
#open(OUTPUTFILE, ">>$output_filename");

#foreach $commentor (keys %reply_ratio) {
#  foreach $reply_parent_commentor (keys %{$reply_ratio{$commentor}}) {
#    print "$commentor -> $reply_parent_commentor: " . $reply_ratio{$commentor}{$reply_parent_commentor} . "\n";
#    print OUTPUTFILE "$commentor\t$reply_parent_commentor\t" . $reply_ratio{$commentor}{$reply_parent_commentor} . "\n";
#  }
#}

#close(OUTPUTFILE);

exit;

