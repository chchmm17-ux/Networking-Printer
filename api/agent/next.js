import { createClient } from '@supabase/supabase-js';
const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, {auth:{persistSession:false}});
function authorized(req){return req.headers.authorization === `Bearer ${process.env.AGENT_TOKEN}`;}
export default async function handler(req,res){
 if(req.method!=='POST')return res.status(405).json({error:'Method not allowed'});
 if(!process.env.AGENT_TOKEN||!authorized(req))return res.status(401).json({error:'Unauthorized'});
 const {data:jobs,error}=await supabase.from('print_jobs').select('*').eq('status','approved').order('created_at',{ascending:true}).limit(1);
 if(error)return res.status(500).json({error:'Could not read approved jobs'});
 if(!jobs?.length)return res.status(200).json({job:null});
 const job=jobs[0];
 const {data:claimed,error:claimError}=await supabase.from('print_jobs').update({status:'printing',updated_at:new Date().toISOString(),message:'Claimed by the Windows print agent.'}).eq('id',job.id).eq('status','approved').select('*').maybeSingle();
 if(claimError)return res.status(500).json({error:'Could not claim job'});
 if(!claimed)return res.status(200).json({job:null});
 const {data:signed,error:signError}=await supabase.storage.from('print-files').createSignedUrl(job.file_path,300);
 if(signError){await supabase.from('print_jobs').update({status:'failed',message:'Could not create a temporary download link.'}).eq('id',job.id);return res.status(500).json({error:'Could not create download link'});}
 return res.status(200).json({job:{id:claimed.id,file_name:claimed.file_name,mime_type:claimed.mime_type,copies:claimed.copies,paper_size:claimed.paper_size,color_mode:claimed.color_mode,page_start:claimed.page_start,page_end:claimed.page_end,download_url:signed.signedUrl}});
}